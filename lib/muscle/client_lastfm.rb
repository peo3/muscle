require 'muscle/audioscrobbler'

module Muscle

class ClientLastfm < AudioScrobbler
	ENDPOINT = 'http://post.audioscrobbler.com/'
	CLIENT_VERSION = "1.0"
	CLIENT_NAME = "tst"

	private

	def optional_entry( taginfo )
		"&m[0]=#{taginfo['mbid']}"
	end
end

end # module Muscle
