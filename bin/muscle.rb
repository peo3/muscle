#! /usr/bin/ruby

require 'observer'
require 'optparse'
require 'curses'
require 'pstore'
require 'find'
require 'thread'
require 'kconv'
require 'logger'

require 'inotify'
require 'taglib'

$KCODE = 'u'

module Muscle
	VERSION = '20061117'

class DirWatcher
	include Observable

	def initialize( dir, logger )
		@dir = dir
		@logger = logger

		@watching_dirs = []
		@inotify = Inotify.new
		@h_wd2dir = {}
		@taginfo_cache = {}
		@q = Queue.new
	end

	def start
		scan_directories
		taginfo_thread

		@watching_dirs.reverse.each do |dirname|
			begin
				wd = @inotify.add_watch(dirname, Inotify::OPEN)
				@h_wd2dir[wd] = dirname
			rescue
				@logger.warn "skip: #{dirname}"
			end
		end

		@t = Thread.new do
			@inotify.each_event do |ev|
				if ev.name =~ /(mp3|ogg)$/
					next unless @h_wd2dir[ev.wd] # need?
					filename =  [@h_wd2dir[ev.wd], ev.name].join('/')

					if (ev.mask & Inotify::OPEN) != 0
						@logger.debug "open: #{ev.name}"
						pass_to_taginfo_thread([filename, ev.wd, Time.now])
					end
				end
			end
		end

		@logger.info "#{@watching_dirs.size.to_s} directories are watched."

		@t.join
	end

	def stop
		@inotify.close
		@t.kill
	end

	private

	def scan_directories
		Find.find(@dir) do |dirname| 
			if ['.svn', 'CVS', 'RCS'].include? File.basename(dirname) or !File.directory?(dirname)
				Find.prune
			else
				files = Dir.glob(dirname + "/*.{ogg,mp3}")
				if not files.empty?
					@logger.debug "add: #{dirname}"
					@watching_dirs << dirname
				end
			end
		end
	end

	def pass_to_taginfo_thread( stuff )
		@q.push stuff
	end

	def get_taginfo( filename )
		return @taginfo_cache[filename] if @taginfo_cache[filename]

		taginfo = {}

		begin
			file = TagLib::File.new(filename)
			['title', 'artist', 'album', 'genre', 'year', 'track', 'length'].each do |info|
				taginfo[info] = file.send(info).to_s.strip.toutf8
			end
		rescue TagLib::BadPath, TagLib::BadFile, TagLib::BadTag, TagLib::BadAudioProperties
			@logger.error $!
			return nil
		end
		file.close

		@taginfo_cache[filename] = taginfo

		taginfo
	end

	def inotify_disable( wd )
		dirname = @h_wd2dir.delete(wd)
		return nil if dirname.nil?
		begin
			@inotify.rm_watch(wd)
		rescue Errno::EINVAL # why?
			@logger.warn $!
			return nil
		end

		yield

		wd = @inotify.add_watch(dirname, Inotify::OPEN)
		@h_wd2dir[wd] = dirname
	end

	def pass_to_clients( taginfo, begintime )
		changed
		begin
			notify_observers(taginfo, begintime)
		rescue
			@logger.error $!
		end
	end

	def get_now_opened_inodes
		#lsofout = IO.popen("/usr/sbin/lsof -O -F pcai0 +D #{@dir}", "r").readlines.join
		lsofout = ""
		IO.popen("lsof -O -F pcai0 +D #{@dir}", "r") do |io|
			lsofout = io.readlines.join
		end
		now_opened_inodes = []
		while lsofout.sub!(/p(\d+)\0c(\w+)\0\na(\w)\0i(\d+)\0\n/,'')
			pid = $1; cmd = $2; mode = $3; ino = $4
			now_opened_inodes << ino.to_i if mode =~ /(r|u)/
		end
		now_opened_inodes
	end

	# get taginfo and pass to clients
	def taginfo_thread
		Thread.new do loop {
			begin

			opened_audiofiles = []
			begin
				opened_audiofiles << @q.pop
			end until @q.empty?
			
			now_opened_inodes = get_now_opened_inodes()
			if now_opened_inodes.empty?
				@logger.debug %Q|cannot get opened inodes.|
				next
			end

			opened_audiofiles.each do |filename, wd, begintime|
				taginfo = nil
				stat = nil

				inotify_disable(wd) do
					stat = File.lstat(filename)
					taginfo = get_taginfo(filename)
				end

				if taginfo.nil? or (not now_opened_inodes.include?(stat.ino))
					@logger.debug %Q|"#{filename}": cannot get taginfo or it is not opened.|
					next
				end

				delay = taginfo['length'].to_i / 2
				delay -= (Time.now - begintime).to_i
				sleep delay if delay > 0

				now_opened_inodes = get_now_opened_inodes()
				if now_opened_inodes.include?(stat.ino)
					#@logger.debug 'cleared queued entries.'
					@q.clear
					pass_to_clients(taginfo, begintime)
				end
				break
			end

			rescue
				@logger.fatal "taginfo thread failed!"
				abort
			end
		} end
	end

end

class UICurses
	include Curses

	def initialize
		@line = 0
	end

	def newline
		@line += 1
		setpos(@line, 0)
	end

	def interaction( client_names, idpass )
		init_screen
		client_names.each do |name|
			echo
			standout
			addstr("[#{name.capitalize}]")
			standend
			newline

			if idpass[name]
				addstr("userid: #{idpass[name]['userid']}")
				userid = idpass[name]['userid']
			else
				addstr('userid: ')
				userid = getstr.chomp
			end
			newline

			noecho
			addstr('passowrd: ')
			password = getstr.chomp

			idpass[name] = {
				'userid' => userid,
				'password' => password
			}

			newline
		end
		close_screen
		$stdout.sync = true

		idpass
	end
end

module Config
	CONFIG_FILE = "#{ENV['HOME']}/.muscle.db"

	def self.read
		db = PStore.new(CONFIG_FILE)
		config = nil
		db.transaction(true) do
  			config = db['config']
		end
		config || {}
	end

	def self.write( config )
		db = PStore.new(CONFIG_FILE)
		db.transaction do
  			db['config'] = config
		end
		File.chmod(0600, CONFIG_FILE)
	end
end
end # module Muscle

class Logger
	class Formatter
		MyFormat = "[%s] %5s : %s\n"
		undef call
		def call(severity, time, progname, msg)
			MyFormat % [format_datetime(time), severity, msg2str(msg)]
		end
	end
end


if __FILE__ == $0
	Thread.abort_on_exception = true
	$:.unshift("lib/") # for use before installation

	OPTS = {}
	OptionParser.new do |opt|
		opt.banner = "usage: #{File.basename($0)} [options] clients watchdir"
		Version = Muscle::VERSION

		opt.on('-l VAL', '--logfile=VAL', 'logfile') {|v|
			OPTS[:logfile] = v
		}
		opt.parse!(ARGV)

		unless ARGV.size == 2
			abort opt.help
		end
	end

	client_names = ARGV[0].split(',')
	dir = ARGV[1]
	logger = Logger.new(OPTS[:logfile] || STDOUT)
	logger.level = $DEBUG ? Logger::DEBUG : Logger::INFO
	logger.datetime_format = "%Y-%m-%d %H:%M:%S"

	client_names.each do |srv|
		begin
			require "muscle/client_#{srv}.rb"
		rescue LoadError
			logger.fatal "can't load 'muscle/client_#{srv}.rb."
			exit 1
		end
	end

	dwatcher = Muscle::DirWatcher.new(dir, logger)
	ui = Muscle::UICurses.new

	client_configs = Muscle::Config.read

	need_interaction = []
	clients = {}
	client_names.each do |name|
		begin
			client = eval("Muscle::Client#{name.capitalize}.new(logger)")
		rescue NameError
			logger.fatal "can't create Client#{name.capitalize}."
			exit 1
		end
		dwatcher.add_observer(client)
		clients[name] = client

		if client_configs[name].nil? or (not client.password_storable?)
			need_interaction << name
		end
	end

	updated_configs = ui.interaction(need_interaction, client_configs.dup)

	updated_configs.each do |name,config|
		client = clients[name]
		next if client.nil?

		client.userid = config['userid']
		if config['storablepassword']
			client.set_storedpassword(config['storablepassword'])
		else
			client.set_password(config['password'])
			if client.password_storable?
				config['storablepassword'] = client.get_storablepassword
			end
		end
		config.delete('password') # Don't save raw password.
	end

	Muscle::Config.write(updated_configs)

	Signal.trap(:INT) do
		dwatcher.stop
	end
	dwatcher.start
end

# vim:ts=3
