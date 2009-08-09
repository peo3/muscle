require 'time'
require 'digest/sha1'
require 'base64'
require 'net/http'
require 'uri'

require 'muscle/clientcommon'

module Muscle

class OtoLog
	include  ClientCommon

	# Note: Inherited clients must define following variables
	# e.g. Parameters for Playlog Client
	# ENDPOINT = 'http://mss.playlog.jp/playlog'
	USERAGENT = "Muscle/#{Muscle::VERSION} (Linux; ja-JP; http://www.kurdt.net/) UNKOWN"

	def initialize( logger )
		@logger = logger # for ClientCommon

		uri = URI.parse(self.class::ENDPOINT)
		@host = uri.host
		@path = uri.path

		@userid = nil
		@password = nil
	end
	attr_accessor :userid

	def set_password( password )
		@password = password
	end

	def set_storedpassword( password )
	end

	def password_storable?
		false
	end

	def get_storablepassword
		nil
	end

	def post( taginfo, begintime )
		unless taginfo_satisfied?(taginfo)
			logerror "lack of taginfo elements: #{taginfo.inspect}"
			return
		end

		begintime = begintime.utc

		wsse = generate_wsse(@userid, @password)

		date = begintime.xmlschema
		duration = (Time.now.utc.to_i - begintime.to_i).to_s

		entry = <<-XML
		<entry xmlns="http://purl.org/atom/ns#" xmlns:otolog="http://otolog.org/ns/music#">
			<otolog:artist>#{taginfo['artist']}</otolog:artist>
			<otolog:album>#{taginfo['album']}</otolog:album>
			<otolog:track>#{taginfo['title']}</otolog:track>
			<otolog:duration>#{duration}</otolog:duration>
			<otolog:date>#{date}</otolog:date>
		</entry>
		XML


		http = Net::HTTP.new(@host)
		response, = http.post(@path, entry, {
			'Content-Type' => 'application/atom+xml',
			'Authorization' => 'WSSE profile="UsernameToken"',
			'Accept' => 'application/x.atom+xml, application/xml, text/xml, */*',
			'Host' => @host,
			'X-WSSE' => wsse,
			'User-Agent' => USERAGENT,
			'Content-Length' => entry.size.to_s
		})
		if response.code == '201'
			loginfo "post success: #{taginfo['title']}"
		else
			logerror "post failed: #{taginfo['title']}"
		end
	end

	private

	def taginfo_satisfied?( taginfo )
		['artist', 'title', 'album'].map {|v|
			taginfo[v] and (not taginfo[v].empty?)
		}.all?
	end

	def generate_wsse(username, password)
		timecreated = Time.now.utc
		created = timecreated.utc.xmlschema
		nonce = Digest::SHA1.digest((Time.now.to_f + rand).to_s)
		nonce_b64 = Base64::encode64(nonce).chomp

		passworddigest = Base64::encode64(Digest::SHA1.digest(nonce + created + password)).chomp

		%Q|UsernameToken Username="#{username}", PasswordDigest="#{passworddigest}", Nonce="#{nonce_b64}", Created="#{created}"|
	end

end

end # module Muscle
