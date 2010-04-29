#!/usr/bin/env ruby
require 'crawlr'

Crawlr::Processor.new.start do |crawlr|
  if ARGV[0]
    File.open(File.expand_path(ARGV[0]), 'r') do |f|
      f.each_line do |line|
        begin
          url = line ? line.strip : ''
          unless url.empty? || crawlr.stored?(url)
            puts "Fetching #{url}"
            crawlr.crawl_page(url) do |malware_page|
              if malware_page.is_ok? && !malware_page.content_type_class?('text/')
                crawlr.store(malware_page, true)
              end
            end
          end
        rescue
          STDERR.write "Failed to fetch: #{url}\n"
        end
      end
    end
  end
end