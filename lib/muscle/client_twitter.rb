require 'muscle/clientcommon'
require 'twitter'

module Muscle

class ClientTwitter
	include  ClientCommon
	MIN_INTERVAL = 30 # minites

	def initialize( logger )
		@logger = logger # for ClientCommon

		@userid = nil
		@password = nil
		@lastpost = Time.at(0)
	end
	attr_accessor :userid

	def post( taginfo, begintime )
		unless taginfo_satisfied?(taginfo)
			logerror "lack of taginfo elements: #{taginfo.inspect}"
			return
		end

		twitter = Twitter::Updater.new(@userid, @password)
		status = %Q|[just listened] "#{taginfo['title']}" by #{taginfo['artist']}|
		now = Time.now
		if (now - @lastpost) > 60*MIN_INTERVAL
			twitter.update(status)
			loginfo "post success: #{taginfo['title']}"
			@lastpost = now
		else
			loginfo "NOT post: #{taginfo['title']}"
		end
	end
	def set_password( password )
		@password = password
	end

	def password_storable?
		false
	end

	def taginfo_satisfied?( taginfo )
		['artist', 'title'].map {|v|
			taginfo[v] and (not taginfo[v].empty?)
		}.all?
	end
end

end # module Muscle
