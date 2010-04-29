require 'crawlr'

Crawlr::Processor.new.start do |crawlr|
  crawlr.crawl_page('http://support.clean-mx.de/clean-mx/viruses') do |page|
    page.search('//tr/td[8]//a[@title="open Url in new Browser at your own risk !"][1]/@href').each do |href|
      puts "Fetching #{href}"
      crawlr.site_agent.get_page(href) do |malware_page|
        if malware_page.is_ok? && !malware_page.content_type_class?('text/')
          av_info = page.search("//tr[td[8][a[@href=\"#{href}\"]]]/td[7]/div/text()[last()]").first.to_s.split(/\xA0/).last
          crawlr.store(malware_page, true, av_info)
        end
      end unless crawlr.stored? href
    end
  end
end