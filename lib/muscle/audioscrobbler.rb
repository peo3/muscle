require 'digest/md5'
require 'net/http'
require 'uri'
require 'cgi'

require 'muscle/clientcommon'

module Muscle

class AudioScrobbler
	include  ClientCommon

	PROTOCOL_VERSION = "1.1"
	# Note: Inherited clients must define following variables
	# e.g. Parameters for Hatena Client
	# ENDPOINT = 'http://music.hatelabo.jp/trackauth'
	# CLIENT_VERSION = "1.0"
	# CLIENT_NAME = "hatena"

	class HandshakeFAILED < StandardError; end
	class HandshakeBADUSER < StandardError; end
	class PostRetry < StandardError; end

	def initialize( logger )
		@logger = logger # for ClientCommon

		@protocol_version = PROTOCOL_VERSION
		uri = URI.parse(self.class::ENDPOINT)
		@host = uri.host
		@path = uri.path
		@client_version = self.class::CLIENT_VERSION
		@client_name = self.class::CLIENT_NAME

		@userid = nil
		@md5_password = nil
	end
	attr_accessor :userid

	def set_password( password )
		@md5_password = Digest::MD5.hexdigest(password)
	end

	def set_storedpassword( md5_password )
		@md5_password = md5_password
	end

	def password_storable?
		true
	end

	def get_storablepassword
		@md5_password
	end

	def post( taginfo, begintime )
		unless taginfo_satisfied?(taginfo)
			logerror "lack of taginfo elements: #{taginfo.inspect}"
			return
		end

		begin
			challenge, url, interval = handshake(@userid)
		rescue HandshakeFAILED, HandshakeBADUSER
			logerror $!
			return
		rescue
			logerror $!
			return
		end

		sleep interval

		date = begintime.utc.strftime('%Y-%m-%d %H:%M:%S')
		md5_response = Digest::MD5.hexdigest(@md5_password + challenge)

		entry = "u=#{@userid}" +
			"&s=#{md5_response}" +
			"&a[0]=#{CGI.escape(taginfo['artist'])}" +
			"&t[0]=#{CGI.escape(taginfo['title'])}" +
			"&b[0]=#{CGI.escape(taginfo['album'])}" +
			"&l[0]=#{taginfo['length']}" +
			"&i[0]=#{date}"
		entry << optional_entry(taginfo)

		uri = URI.parse(url)
		http = Net::HTTP.new(uri.host)
		interval = 0
		begin
			response = http.post(uri.path, entry, {
				"content-type" => "application/x-www-form-urlencoded",
			})

			res = response.body.split("\n")
			case res[0]
			when /^OK/
				loginfo "post success: #{taginfo['title']}"
			when /^FAILED/
				if res[0] =~ /Plugin bug: Not all request variables are set( - no POST parameters\.)?$/
					res[1] =~ /INTERVAL (\d+)/
					interval = $1.to_i
					raise PostRetry
				end
				logerror "post failed with FAILED: #{taginfo['title']}"
			when /^BADAUTH/
				logerror "post failed with BADAUTH: #{taginfo['title']}"
			else
				logfatal "post failed with UNKNOWN reason!: #{taginfo['title']}"
			end
		rescue PostRetry
			sleep interval
			loginfo "retrying..."
			retry
		rescue
			logerror $!
		end
	end

	private

	def taginfo_satisfied?( taginfo )
		['artist', 'title', 'album', 'length'].map {|v|
			taginfo[v] and (not taginfo[v].empty?)
		}.all?
	end

	def optional_entry( taginfo )
		""
	end

	def handshake( user )
		http = Net::HTTP.new(@host)
		args = "?hs=true" +
			"&p=#{@protocol_version}" +
			"&c=#{@client_name}" + 
			"&v=#{@client_version}" +
			"&u=#{user}"
		response = http.get(@path + args)
		res = response.body.split("\n")
		case res[0]
		when /^UPTODATE/
			challenge = res[1]
			url = res[2]
			res[3] =~ /INTERVAL (\d+)/
			interval = $1.to_i
		when /^UPDATE/
		when /^FAILED/
			res[0] =~ /^FAILED (.+)$/
			raise HandshakeFAILED, $1
		when /^BADUSER/
			raise HandshakeBADUSER
		end
		return challenge, url, interval
	end

end

end # module Muscle

