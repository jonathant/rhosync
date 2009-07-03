require 'net/http'
require 'uri'

# this class performs push to notify devices to retrieve data, all via BES server PAP push
# set APP_CONFIG['bbserver] in your settings.yml
class Blackberry < Device
  
  def ping(callback_url,message=nil,vibrate=nil,badge=nil,sound=nil) # notify the BlackBerry device via PAP
    p "Pinging Blackberry device via BES push: " + pin 
    set_ports
    setup_template
    data=build_payload(callback_url,message,vibrate)
    headers={"X-WAP-APPLICATION-ID"=>"/",
             "X-RIM-PUSH-DEST-PORT"=>self.deviceport,
             "CONTENT-TYPE"=>'multipart/related; type="application/xml"; boundary=asdlfkjiurwghasf'}
    begin
      @result=http_post(url,data,headers)   
      p "Returning #{@result.inspect}"
    rescue
      p "Failed to post "
      @result="post failure"
    end
    @result
  end
  
  private
  
  def set_ports    
    self.host=APP_CONFIG[:bbserver]  # make sure to set APP_CONFIG[:bbserver] in settings.yml
    self.serverport="8080"
    self.deviceport||="100"
  end

  def http_post(address,data,headers)
    uri=URI.parse(address)
    p "URI: #{uri}"
    response=Net::HTTP.new(uri.host,uri.port).start do |http|
      request = Net::HTTP::Post.new(uri.path,headers)
      request.body = data
      http.request(request)
    end
    response
  end

  def build_payload(callback_url,message,vibrate)
    setup_template
    data="do_sync="+callback_url + "\r\n"
    popup||=message # supplied message
    popup||=APP_CONFIG[:sync_popup]
    popup||="You have new data"
    (data = data + "show_popup="+ popup + "\r\n") if popup
    vibrate=APP_CONFIG[:sync_vibrate]
    (data = data + "vibrate="+vibrate.to_s) if vibrate
    post_body = @template
    post_body.gsub(/--RAND_ID--/, push_id).gsub(/--DEVICE_PIN_HEX--/, self.pin.to_i.to_s(base=16).upcase).gsub(/--CONTENT--/, data)
  end
  
  def push_id
    (rand * 100000000).to_i.to_s
  end
  
  def setup_template
    @template =
<<-DESC
--asdlfkjiurwghasf
Content-Type: application/xml; charset=UTF-8

<?xml version="1.0"?>
<!DOCTYPE pap PUBLIC "-//WAPFORUM//DTD PAP 2.0//EN" 
  "http://www.wapforum.org/DTD/pap_2.0.dtd" 
  [<?wap-pap-ver supported-versions="2.0"?>]>
<pap>
<push-message push-id="pushID:--RAND_ID--" ppg-notify-requested-to="http://localhost:7778">

<address address-value="WAPPUSH=--DEVICE_PIN_HEX--%3A100/TYPE=USER@rim.net"/>
<quality-of-service delivery-method="confirmed"/>
</push-message>
</pap>
--asdlfkjiurwghasf
Content-Type: text/plain

--CONTENT--
--asdlfkjiurwghasf--
DESC
    @template.gsub!(/\n/,"\r\n")
  end
  
  def url  # this is the logic for doing BES server PAP push.  Takes host & serverport\
    if host and serverport
      @url="http://"+ host + "\:" + serverport + "/pap"
    else
      p "Do not have all values for URL"
      @url=nil
    end
  end
  
  def push_id
    (rand * 100000000).to_i.to_s
  end
end