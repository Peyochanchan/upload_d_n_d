# frozen_string_literal: true

module UploadDND
  module Generators
    class PolicyGenerator < Rails::Generators::Base
      source_root File.expand_path('templates', __dir__)

      desc "Generate a Pundit policy for UploadDND temporary attachments"

      def create_policy_file
        template "policies/upload_d_n_d_temporary_attachment_policy.rb",
                 "app/policies/upload_d_n_d_temporary_attachment_policy.rb"
      end

      def show_readme
        readme "POLICY_README" if behavior == :invoke
      end
    end
  end
end
