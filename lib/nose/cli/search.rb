require 'formatador'
require 'ostruct'
require 'json'

module NoSE
  module CLI
    # Add a command to run the advisor for a given workload
    class NoSECLI < Thor
      desc 'search NAME', 'run the workload NAME'
      option :max_space, type: :numeric, default: Float::INFINITY,
                         aliases: '-s'
      option :enumerated, type: :boolean, default: false, aliases: '-e'
      option :read_only, type: :boolean, default: false
      option :mix, type: :string, default: 'default'
      option :objective, type: :string, default: 'cost',
                         enum: %w(cost space indexes)
      option :format, type: :string, default: 'txt',
                      enum: %w(txt json yml), aliases: '-f'
      option :output, type: :string, default: nil, aliases: '-o'
      def search(name)
        # Get the workload and cost model
        workload = Workload.load name
        workload.mix = options[:mix].to_sym \
          unless options[:mix] == 'default' && workload.mix != :default
        workload.remove_updates if options[:read_only]
        cost_model = get_class('cost', options[:cost_model][:name]).new(**options[:cost_model])

        # Execute the advisor
        objective = case options[:objective]
                    when 'cost'
                      Search::Objective::COST
                    when 'space'
                      Search::Objective::SPACE
                    when 'indexes'
                      Search::Objective::INDEXES
                    end

        result = search_result workload, cost_model, options[:max_space],
                               objective
        return if result.nil?

        # Output the results in the specified format
        file = options[:output].nil? ? $stdout :
                                       File.open(options[:output], 'w')
        begin
          send(('output_' + options[:format]).to_sym,
               result, file, options[:enumerated])
        ensure
          file.close unless options[:output].nil?
        end
      end
    end
  end
end
