#!/usr/bin/env ruby
# this ones seems to yield mostly image, document and js exploits
require 'crawlr'

Crawlr::Processor.new.start do |crawlr|
  crawlr.crawl_page('http://security.technosoftcorp.com/ss/ss_frame_exploit_url.htm') do |page|
    page.search('//table[@class="vuldisp"]//tr/td[1]/text()').each do |href|
      url = href.to_s.split.first
      puts "Fetching #{url}"
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