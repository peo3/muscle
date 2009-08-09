require 'logger'
require 'observer'

module Muscle

module ClientCommon
	# requires @logger in Class which includes this module

	def update( taginfo, begintime )
		Thread.new do
			begin
				logdebug("posting: " + taginfo['title'])
				post(taginfo, begintime)
			rescue TimeoutError
				logerror $!
			rescue
				logerror $!
			end
		end
	end

	private

	def parse_caller(at)
		if /^(.+?):(\d+)(?::in `(.*)')?/ =~ at
			file = $1
			line = $2.to_i
			method = $3
			[file, line, method]
		else
			['', 0, '']
		end
	end

	def myself
		self.class.to_s.sub(/^Muscle::Client/, '')
	end

	def logdebug( str )
		@logger.debug "[#{myself}] " + str
	end

	def loginfo( str )
		@logger.info "[#{myself}] " + str
	end

	def logwarn( str )
		@logger.warn "[#{myself}] " + str
	end

	def logerror( str )
		file, line, method = parse_caller(caller.first)
		@logger.error "[#{myself}](#{method}) " + str
	end

	def logfatal( str )
		file, line, method = parse_caller(caller.first)
		@logger.fatal "[#{myself}](#{method}) " + str
	end

end

end # module Muscle
