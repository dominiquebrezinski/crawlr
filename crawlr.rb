require 'rubygems'
require 'dm-core'
require 'dm-types'
require 'spidr'
require 'digest'
require 'fileutils'

module Crawlr
  class Site
    include DataMapper::Resource
    
    property :id,               Serial
    property :url,              URI
    property :last_visited_at,  DateTime
    property :created_at,       DateTime
    
    has n, :pages
  end
  
  class Page
    include DataMapper::Resource

    property :id,           Serial
    property :url,          URI
    property :hash,         String, :length => 40
    property :stored_file,  FilePath
    property :content_type, String
    property :visited_at,   DateTime
    property :created_at,   DateTime
    
    belongs_to :site
    
    def self.processed
      all(:visited_at.not => nil)
    end
    
    def self.not_processed
      all(:visited_at => nil)
    end
    
    def self.generate_hash(content)
      Digest::SHA1.hexdigest(content) if content
    end
  end
  
  class Bootstrap
    def initialize(database = nil)
      DataMapper::Logger.new($stdout, :debug)
      DataMapper.setup(:default, database || Crawlr::load_database_parameters || 'mysql://root:n1h!lOne@localhost/crawlr?socket=/tmp/mysql.sock')
      DataMapper.auto_migrate!
      ::FileUtils.mkdir 'extracted', :mode => 0740
    end
  end
  
  class Processor
    include Spidr
    
    attr_reader :site, :site_agent
    
    def initialize(database = nil)
      DataMapper::Logger.new($stdout, :debug)
      DataMapper.setup(:default, database || Crawlr::load_database_parameters || 'mysql://root:n1h!lOne@localhost/crawlr?socket=/tmp/mysql.sock')
      unless File.exists? 'extracted'
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
      site_agent.start_at(url, &block)
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
    
    def store(page, to_disk = false)
      unless page.nil?
        content_hash = Crawlr::Page.generate_hash(page.body)
        if to_disk
          f_name = File.expand_path("extracted/#{content_hash}")
          File.open(f_name, File::CREAT|File::EXCL|File::WRONLY, 0640) do |f|
            f.write(page.body)
          end
        end
        Crawlr::Page.first_or_create({:url => page.url, :hash => content_hash},
                                     {:site_id => @site.id,
                                      :url => page.url,
                                      :hash => content_hash,
                                      :stored_file => to_disk ? f_name : nil,
                                      :content_type => page.content_type,
                                      :visited_at => DateTime.now})
      else
        false
      end
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
  end
end

#Crawlr::Processor.new.start do |crawlr|
#  crawlr.crawl_site('http://umindr.com') do |page|
#    if m = page.regex_search(/network like a pro/i)
#      puts "We seem to be working! #{m[0]}"
#      #crawlr.store(page, true)
#    end
#  end
#end
