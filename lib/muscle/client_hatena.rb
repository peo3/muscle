require 'muscle/audioscrobbler'

module Muscle

class ClientHatena < AudioScrobbler
	ENDPOINT = 'http://music.hatelabo.jp/trackauth'
	CLIENT_VERSION = "1.0"
	CLIENT_NAME = "hatena"

	private

	def optional_entry( taginfo )
		"&p[0]=0&r[0]=0&c[0]=#{taginfo['track']}&f[0]=0"
	end
end

end # module Muscle
