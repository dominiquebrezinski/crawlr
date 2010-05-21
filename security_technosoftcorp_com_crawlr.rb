#!/usr/bin/env ruby
# this ones seems to yield mostly image, document and js exploits
require 'crawlr'

Crawlr::Processor.new(ARGV[0]).start do |crawlr|
  crawlr.crawl_page('http://security.technosoftcorp.com/ss/ss_frame_exploit_url.htm') do |page|
    page.search('//table[@class="vuldisp"]//tr/td[1]/text()').each do |href|
      url = href.to_s.split.first
      unless crawlr.stored? url
        puts "Fetching #{url}"
        page = crawlr.site_agent.head_page(url)
        if page && page.content_length < Crawlr::DOWNLOAD_BYTE_LIMIT
          begin
          crawlr.site_agent.get_page(url) do |malware_page|
            if malware_page.is_ok? && !malware_page.content_type_class?('text/')
              crawlr.store(malware_page, true)
            end
          end unless crawlr.stored? url
          rescue
          end
        end
      end
    end
  end
end