#!/usr/bin/env ruby
require 'crawlr'
# first commandline arg is the list or urls to fetch
# optional second commandline argument is the extract directory to use
Crawlr::Processor.new(ARGV[1]).start do |crawlr|
  if ARGV[0]
    File.open(File.expand_path(ARGV[0]), 'r') do |f|
      f.each_line do |line|
        begin
          url = line ? line.strip : ''
          unless url.empty? || crawlr.stored?(url)
            puts "Fetching #{url}"
            page = crawlr.site_agent.head_page(url)
            if page && page.content_length < Crawlr::DOWNLOAD_BYTE_LIMIT
              crawlr.crawl_page(url) do |malware_page|
                if malware_page.is_ok? && !malware_page.content_type_class?('text/')
                  crawlr.store(malware_page, true)
                else
                  crawlr.store(malware_page || page)
                end
              end
            else
              crawlr.seen(url)
            end
          end
        rescue
          STDERR.write "Failed to fetch: #{url}\n"
        end
      end
    end
  end
end