#!/usr/bin/env ruby
require 'crawlr'

# use the first agrument as the extract directory if it is present
Crawlr::Processor.new(ARGV[0]).start do |crawlr|
  crawlr.crawl_page('http://support.clean-mx.de/clean-mx/viruses') do |page|
    puts "Got top page"
    page.search('//tr/td[8]//a[@title="open Url in new Browser at your own risk !"][1]/@href').each do |href|
      unless crawlr.stored? href
        puts "Fetching #{href}"
        page = crawlr.site_agent.head_page(href)
        if page && page.content_length < Crawlr::DOWNLOAD_BYTE_LIMIT
          crawlr.site_agent.get_page(href) do |malware_page|
            if malware_page.is_ok? && !malware_page.content_type_class?('text/')
              av_info = page.search("//tr[td[8][a[@href=\"#{href}\"]]]/td[7]/div/text()[last()]").first.to_s.split(/\xA0/).last
              crawlr.store(malware_page, true, av_info)
            else
              crawlr.store(malware_page || page)
            end
          end
        else
          crawlr.seen(href)
        end
      end
    end
  end
end