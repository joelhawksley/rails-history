require 'csv'
require 'date'
require 'json'
require 'pstore'

class RailsHistory
  attr_reader :path

  def initialize(path)
    @path = path
  end

  def run
    cache = PStore.new("cache.pstore")
    stats = []
    start = Time.now
    current_date = nil
    output_filename = "output-#{Time.now.to_i}"

    # https://docs.ruby-lang.org/en/master/PStore.html
    cache.transaction do
    # https://stackoverflow.com/questions/5188914/how-to-show-the-first-commit-by-git-log
      initial_commit =
        if cache[:initial_commit]
          cache[:initial_commit]
        else
          cache[:initial_commit] = `cd #{path}; git log --pretty=oneline --format=format:%H --reverse | head -1`
        end

      # https://git-scm.com/docs/pretty-formats
      current_date =
        if cache[:initial_date]
          cache[:initial_date]
        else
          cache[:initial_date] = `cd #{path}; git show --no-patch --no-notes --pretty='%cs' #{initial_commit}`.strip
        end
    end

    current_date = "2024-11-19" # comment out to run for all

    CSV.open("#{output_filename}.csv", 'wb') do |csv|
      headers_added = false

      while Date.parse(current_date) < Date.today
        puts "Current date: #{current_date}"

        sha = cache.transaction do
          if cache[current_date].to_s.length > 0
            cache[current_date]
          else
            `cd #{path}; git checkout master`
            cache[current_date] = `cd #{path}; git rev-list master --after="#{current_date}" --reverse HEAD | head -n 1`
          end
        end

        with_timing("Checking out #{sha}") do
          `cd #{path}; git checkout #{sha}`
        end

        previous_date = (Date.parse(current_date) << 1).to_s

        # disclose counts include routes behind feature flags

        data = {
          date: current_date,
          sha: sha,
          css: get_stats_for_lookup("'*.css' ':!:vendor/*' ':!:node_modules/*' ':!:test/*'"),
          scss: get_stats_for_lookup("'*.scss' ':!:vendor/*' ':!:node_modules/*' ':!:test/*'"),
          erb: get_stats_for_lookup("'app/views/*.erb' 'packages/**/app/views/*.erb'"),
          erb_nodes: get_stats_for_lookup("'app/views/*.erb' 'packages/**/app/views/*.erb'", /(%>)|<\/|\/>/),
          view_components: get_stats_for_lookup("'app/components/*.html.erb' 'app/components/*.rb'"),
          view_components_nodes: get_stats_for_lookup("'app/components/*.html.erb' 'app/components/*.rb'", /(%>)|<\/|\/>/),
          pvc_buttons: get_stats_for_lookup("'app/components/*.html.erb' 'app/components/*.rb'", /(Button.new|ButtonComponent.new)/),
          prc_buttons: get_stats_for_lookup("'*.tsx' ':!:*test.tsx' ':!:vendor/*' ':!:node_modules/*' ':!:test/*'", /\<Button/),
          coffee: get_stats_for_lookup("'*.coffee' ':!:vendor/*' ':!:node_modules/*' ':!:test/*'"),
          js: get_stats_for_lookup("'*.js' ':!:*test.js' ':!:vendor/*' ':!:node_modules/*' ':!:test/*'"),
          ts: get_stats_for_lookup("'*.ts' ':!:*test.ts' ':!:vendor/*' ':!:node_modules/*' ':!:test/*'"),
          tsx: get_stats_for_lookup("'*.tsx' ':!:*test.tsx' ':!:vendor/*' ':!:node_modules/*' ':!:test/*'"),
          tsx_nodes: get_stats_for_lookup("'*.tsx' ':!:*test.tsx' ':!:vendor/*' ':!:node_modules/*' ':!:test/*'", /<\/|\/>/),
          controllers: get_stats_for_lookup("'*_controller.rb' ':!:vendor/*' ':!:test/*'"),
          models: get_stats_for_lookup("'app/models/*.rb' 'packages/**/app/models/*.rb'"),
          get_routes: get_stats_for_lookup("'config/routes.rb'", /get /).values.first,
          react_routes_per_controller: get_stats_for_lookup("'*_controller.rb' ':!:vendor/*' ':!:test/*'", /render_react_app/),
          unique_contributors: `cd #{path}; git shortlog -s -n --all --since #{previous_date} --before #{current_date}`.lines.length
        }

        keys = data.keys

        if !headers_added
          csv << keys.map do |key|
            if data[key].is_a?(Hash)
              [key, "#{key}_files"]
            else
              key
            end
          end.flatten

          headers_added = true
        end

        csv << keys.map do |key|
          if data[key].is_a?(Hash)
            # exclude length key from sum
            [data[key].values.sum - data[key][:length], data[key][:length]]
          else
            data[key].to_s.strip
          end
        end.flatten

        current_date = (Date.parse(current_date) >> 1).to_s
      end
    end

    puts
    puts "Completed in #{(Time.now - start).to_i} seconds"
  end

  def with_timing(message = nil)
    puts
    puts message if message

    start = Time.now
    result = yield

    #puts result if result && result.length > 0
    puts "Completed in #{(Time.now - start).to_i} seconds"
    puts

    result
  end

  def get_stats_for_lookup(lookup, regex = nil)
    with_timing(lookup) do
      list = `cd #{path}; git ls-files #{lookup}`

      out = {}

      if list.length > 0
        list.lines.each do |line|
          begin
            out[line.strip] =
              if regex
                File.read(File.join(__dir__, "#{path}", line.strip)).scan(regex).size
              else
                File.read(File.join(__dir__, "#{path}", line.strip)).lines.length
              end
          rescue => e
            puts e.message
          end
        end
      end

      out[:length] = list.lines.length

      out
    end
  end
end

path = ARGV[0]

unless path
  puts "Please provide a relative path:"
  puts "ruby script.rb ../github"
end

RailsHistory.new(path).run
