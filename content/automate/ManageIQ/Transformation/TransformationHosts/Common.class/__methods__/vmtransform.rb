module ManageIQ
  module Automate
    module Transformation
      module TransformationHost
        module Common
          class VMTransform
            def initialize(handle = $evm)
              @debug = false
              @handle = handle
            end

            def set_retry(message = nil, interval = '1.minutes')
              @handle.log(:info, message) if message.present?
              @handle.root['ae_result'] = 'retry'
              @handle.root['ae_retry_interval'] = interval
            end

            def main
              require 'json'

              factory_config = @handle.get_state_var(:factory_config)
              raise "No factory config found. Aborting." if factory_config.nil?

              task = @handle.root['service_template_transformation_plan_task']

              # Get or create the virt-v2v start timestamp
              start_timestamp = task.get_option(:virtv2v_started_on) || Time.now.utc.strftime('%Y-%m-%d %H:%M:%S')

              # Retrieve transformation host
              transformation_host = @handle.vmdb(:host).find_by(:id => task.get_option(:transformation_host_id))

              @handle.log(:info, "Transformation - Started On: #{start_timestamp}")

              destination_ems = @handle.vmdb(:ext_management_system).find_by(:id => task.get_option(:destination_ems_id))
              max_runners = Transformation::TransformationHosts::Common::Utils.ems_max_runners(destination_ems, factory_config)
              if Transformation::TransformationHosts::Common::Utils.get_runners_count_by_ems(destination_ems, factory_config) >= max_runners
                @handle.log(:info, "Too many transformations running [#{max_runners}]. Retrying.")
              else
                wrapper_options = ManageIQ::Automate::Transformation::TransformationHosts::Common::Utils.virtv2vwrapper_options(task)

                # WARNING: Enable at your own risk, as it may lead to sensitive data leak
                # @handle.log(:info, "JSON Input:\n#{JSON.pretty_generate(wrapper_options)}") if @debug

                @handle.log(:info, "Connecting to #{transformation_host.name} as #{transformation_host.authentication_userid}") if @debug
                @handle.log(:info, "Executing '/usr/bin/virt-v2v-wrapper.py'")
                result = Transformation::TransformationHosts::Common::Utils.remote_command(task, transformation_host, "/usr/bin/virt-v2v-wrapper.py", wrapper_options.to_json)
                raise result[:stderr] unless result[:rc].zero?

                # Record the wrapper files path
                @handle.log(:info, "Command stdout: #{result[:stdout]}") if @debug
                task.set_option(:virtv2v_wrapper, JSON.parse(result[:stdout]))

                # Record the status in the task object
                task.set_option(:virtv2v_started_on, start_timestamp)
                task.set_option(:virtv2v_status, 'active')
              end

              set_retry if task.get_option(:virtv2v_started_on).nil?
            rescue => e
              @handle.set_state_var(:ae_state_progress, 'message' => e.message)
              raise
            end
          end
        end
      end
    end
  end
end

if $PROGRAM_NAME == __FILE__
  ManageIQ::Automate::Transformation::TransformationHost::Common::VMTransform.new.main
end
