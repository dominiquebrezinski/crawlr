require 'rubygems'
require 'dm-core'
require 'dm-types'
require 'spidr'
require 'digest'
require 'fileutils'
require 'system_timer'

module Crawlr
  DOWNLOAD_BYTE_LIMIT = 10485760 # 10 MB
  
  class Site
    include DataMapper::Resource
    
    property :id,               Serial, :unique_index => :id
    property :url,              URI, :index => true
    property :last_visited_at,  DateTime
    property :created_at,       DateTime
    
    has n, :pages
  end
  
  class Page
    include DataMapper::Resource

    property :id,           Serial, :unique_index => :id
    property :url,          URI, :index => true
    property :hash,         String, :length => 64, :index => true
    property :stored_file,  FilePath
    property :content_type, String
    property :av_info,      String, :length => 100
    property :visited_at,   DateTime, :index => true
    property :created_at,   DateTime, :index => true
    
    belongs_to :site
    
    def self.processed
      all(:visited_at.not => nil)
    end
    
    def self.not_processed
      all(:visited_at => nil)
    end
    
    def self.generate_hash(content)
      Digest::SHA256.hexdigest(content) if content
    end
  end
  
  def self.bootstrap(extract_dir = 'extracted', database = nil)
    begin
      ::FileUtils.mkdir extract_dir, :mode => 0750
      DataMapper::Logger.new($stdout, :debug)
      DataMapper.setup(:default, database || Crawlr::load_database_parameters)
      # this is does a drop table and is destructive
      DataMapper.auto_migrate!
      puts "Crawlr is bootstrapped and ready to rock!"
    rescue Errno::EEXIST
      STDERR.write "It appears Crawlr has been bootstrapped already.\n"
    end
  end
  
  class Processor
    include Spidr
    
    attr_reader :site, :site_agent
    
    def initialize(extract_dir = nil, database = nil)
      DataMapper::Logger.new($stdout, :warn)
      DataMapper.setup(:default, database || Crawlr::load_database_parameters)
      @extract_dir = extract_dir || 'extracted'
      unless File.exists? @extract_dir
        STDERR.print("Warning: the 'extracted' directory does not exist.\nHas the Crawlr been bootstrapped?")
        exit
      end
    end
  
    def start(&block)
      yield self
    end
    
    def create_agent_for_site(url, options = {})
      url = URI(url.to_s)
      @site = Crawlr::Site.first_or_create({:url => url},
                                           {:url => url, :created_at => DateTime.now})
      @site.last_visited_at = DateTime.now
      @site.save
      @site_agent = Agent.new(options.merge(:host => url.host))
    end
    
    def crawl_site(url, options = {}, &block)
      url = URI(url.to_s)
      unless site_agent
        create_agent_for_site(url, options)
      end
      if site_agent
        site_agent.start_at(url, &block)
      else
        false
      end
    end
    
    def crawl_page(url, options = {}, &page_processor)
      url = URI(url.to_s)
      unless site_agent
        create_agent_for_site(url, options)
      end
      if site_agent
        page = site_agent.get_page(url)
        (page && page.is_ok?) ? yield(page) : false
      else
        false
      end
    end
    
    # Do form-based authentication for a site. Requires an initialized agent
    # for the site is already created.
    # +auth_form_url+::
    #    URL to login form
    # +&form_processor+::
    #    block that receives the Page object for the login form and is responsible
    #    for returning an array where the first member is the URL to post the
    #    authentication data to and the last member is the authentication form
    #    data, including any anti-CSRF form authenticators etc.
    # +@return+::
    #    true on success or false on failure
    def form_authenticate(auth_form_url, &form_processor)
      if site_agent
        form_page = site_agent.get_page(auth_form_url)
        auth_url, auth_post_data = *form_processor.call(form_page)
        if auth_url && auth_post_data
          response = site_agent.post_page(auth_url, auth_post_data)
          response.nil? ? false : response
        else
          false
        end
      else
        false
      end
    end
    
    def stored?(url)
      Crawlr::Page.first :url => url
    end
    
    def store(page, to_disk = false, av_info = '')
      unless page.nil?
        content_hash = Crawlr::Page.generate_hash(page.body)
        if to_disk
          f_name = File.expand_path("#{@extract_dir}/#{content_hash}")
          begin
            File.open(f_name, File::CREAT|File::EXCL|File::WRONLY, 0640) do |f|
              f.write(page.body)
            end
          rescue Errno::EEXIST
            STDERR.write "File already exists: #{content_hash}\n"
          end
        end
        stored_page = Crawlr::Page.first_or_create({:url => page.url, :hash => content_hash},
                                                   {:site_id => @site.id,
                                                    :url => page.url,
                                                    :hash => content_hash,
                                                    :stored_file => to_disk ? f_name : nil,
                                                    :content_type => page.content_type[0,50],
                                                    :av_info => (av_info || '').to_s[0,100],
                                                    :created_at => DateTime.now})
        stored_page.visited_at = DateTime.now
        stored_page.save
      else
        false
      end
    end
    
    def seen(url)
      stored_page = Crawlr::Page.first_or_create({:url => url},
                                                 {:site_id => @site.id,
                                                  :url => url,
                                                  :created_at => DateTime.now})
      stored_page.visited_at = DateTime.now
      stored_page.save
    end
  end
  
  def self.load_database_parameters
    begin
      hash = YAML.load(File.new("database.yml"))
      hash['production'] if hash
    rescue
      nil
    end
  end
end

module Spidr
  class Page
    def regex_search(regex)
      return nil if (body.nil? || body.empty?)
      regex.match(body)
    end
    
    def content_type_class?(type_class)
      is_content_type?(type_class)
    end
    
    def content_length
      (@response['Content-Length'] || 0).to_i
    end
  end
  class Agent
    def get_page(url, timeout = 60)
      begin
        url = URI(url.to_s)
      rescue URI::InvalidURIError
        return nil
      end
      prepare_request(url) do |session,path,headers|
        new_page = nil
        SystemTimer.timeout_after(timeout.to_f) do
          new_page = Page.new(url,session.get(path,headers))
        end
        unless new_page.nil?
          # save any new cookies
          @cookies.from_page(new_page)

          yield new_page if block_given?
          new_page
        end
      end
    end
    
    def head_page(url, timeout = 3)
      begin
        url = URI(url.to_s)
      rescue URI::InvalidURIError
        return nil
      end
      prepare_request(url) do |session,path,headers|
        new_page = nil
        SystemTimer.timeout_after(timeout.to_f) do
          new_page = Page.new(url,session.head(path,headers))
        end
        unless new_page.nil?
          # save any new cookies
          @cookies.from_page(new_page)

          yield new_page if block_given?
        end
        new_page
      end
    end
  end
end

