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
      option :format, type: :string, default: 'txt',
                      enum: %w(txt json yml), aliases: '-f'
      option :output, type: :string, default: nil, aliases: '-o'
      def search(name)
        # Get the workload and cost model
        workload = get_workload name
        workload.remove_updates if options[:read_only]
        config = load_config
        cost_model = get_class 'cost', config[:cost_model][:name]

        # Execute the advisor
        result = search_result workload, cost_model, options[:max_space]

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

      private

      # Find the indexes with the given space constraint
      def find_indexes(workload, enumerated_indexes, space, cost_model)
        Search::Search.new(workload, cost_model) \
          .search_overlap enumerated_indexes, space
      end
    end
  end
end
