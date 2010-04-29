require 'crawlr'

Crawlr::Processor.new.start do |crawlr|
  crawlr.create_agent_for_site('https://cfp.blackhat.com/')
  
  authed = crawlr.form_authenticate('https://cfp.blackhat.com/login') do |auth_form|
    post_url = auth_form.search('//form[1]/@action').first
    username_field = auth_form.search('//form[1]//input[@id="user_login"]/@name').first
    password_field = auth_form.search('//form[1]//input[@id="user_password"]/@name').first
    form_authenticator = auth_form.search('//form[1]//input[@name="authenticity_token"]/@value').first
    [post_url, "#{username_field}=fufu&#{password_field}=password&authenticity_token=#{form_authenticator}"]
  end
  
  page_processor = Proc.new do |page|
    puts page.search('//title').first
  end
  
  if authed.is_redirect?
    start_url = authed.search('//a[@href]/@href').first
    crawlr.crawl_site(start_url, &page_processor)
  elsif authed.is_ok?
    authed.urls.each {|url| crawlr.site_agent.enqueue(url) }
    crawlr.site_agent.run(&page_processor)
  else
    puts "Authentication failed!"
  end
end