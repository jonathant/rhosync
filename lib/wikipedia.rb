require 'net/http'
require 'uri'
    
class Wikipedia < SourceAdapter
  attr_accessor :search_query
  
  
  def initialize(source,credential)
    puts "Wikipedia initialize with #{source.inspect.to_s}"
    
    super(source,credential)
  end
  
  def ask(question)
    puts "Wikipedia ask with #{question.inspect.to_s}\n"
    
    @search_query = question[:search]
    
    data = ask_wikipedia @search_query
    
    # return array of objects that correspond
    [ ObjectValue.new(:source_id=>@source.id, :object => @search_query, :attrib => "data_length", :value => data.length.to_s),
      ObjectValue.new(:source_id=>@source.id, :object => @search_query, :attrib => "data", :value => data) ]
  end
  
  ####### begin legacy interface #######
    
  def query
    @search_query ||= "::Home"
  end
 
  def sync
    puts "Wikipedia sync with #{@search_query}"
    
    data = ask_wikipedia @search_query
    
    ObjectValue.create(:source_id=>@source.id, :object => @search_query, :attrib => "data_length", :value => data.length.to_s)
    ObjectValue.create(:source_id=>@source.id, :object => @search_query, :attrib => "data", :value => data)
  end
 
  # [{"name"=>"search", "value"=>"diamond"}]
  def create(name_value_list)
    puts "Wikipedia create"
 
    puts name_value_list.inspect.to_s
    @search_query=name_value_list[0]["value"]
  end
  
  ####### end legacy interface #######
  
  protected
  
  def wiki_name(raw_string)
    raw_string.gsub(" ", "_")
  end
  
  def ask_wikipedia(search)
    path = "/wiki/#{wiki_name(search)}"
 
    # temporarily we hardcode these headers which are required by m.wikipedia.org
    headers = {
      'User-Agent' => 'Mozilla/5.0 (iPhone; U; CPU like Mac OS X; en) AppleWebKit/420+ (KHTML, like Gecko) Version/3.0 Mobile/1C28'
    }
    
    response, data = fetch(path, headers)
    data = rewrite_urls(data)
    
    [data].pack("m").gsub("\n", "")
  end
  
  # follow redirects here on the server until we are at final page
  def fetch(path, headers, limit = 10)
    raise ArgumentError, 'HTTP redirect too deep' if limit == 0
 
    http = Net::HTTP.new(@source.url)
    response, data = http.get(path, headers)
    
    puts "Code = #{response.code}"
    puts "Message = #{response.message}"
    response.each {|key, val|
      puts key + ' = ' + val
    }
    
    case response
    when Net::HTTPSuccess then
      nil
    when Net::HTTPRedirection then
      # location has changed so in effect new search query
      @search_query = response['location'].sub('/wiki/', '')
      response, data = fetch(response['location'], headers, limit - 1)
    else
      response.error!
    end
    
    return response, data
  end
 
  #
  # wikipedia pages are shown in an iframe in the Rhodes app
  # here we rewrite URLs so that they work in that context
  #
  # rewrite URLs of the form:
  # <a href="/wiki/Feudal_System"
  # to
  # <a href="/Wikipedia/WikipediaPage/{Feudal_System}/fetch"
  #
  
  # Did you mean: <a href="/w/index.php?title=Special:Search&amp;search=blackberry&amp;fulltext=Search&amp;ns0=1&amp;redirs=0" title="Special:Search">
  # <em>blackberry</em>
  # </a>
  
  def rewrite_urls(html)
    # images
    html = html.gsub('<img src="/images/logo-en.png" />', '<img src="http://en.m.wikipedia.org/images/logo-en.png" />')
    # javascripts
    html = html.gsub('window.location', 'top.location')
    html = html.gsub('/wiki/::Random', '/Wikipedia/WikipediaPage/{::Random}/fetch')
    #stylesheets
    html = html.gsub('<link href=\'/stylesheets/application.css\'', '<link href=\'http://m.wikipedia.org/stylesheets/application.css\'')
    # links to other articles
    html.gsub(/href=\"\/wiki\/([\w\(\)%:\-\,._]*)\"/i,'href="/Wikipedia/WikipediaPage/{\1}/fetch" target="_top"')
  end