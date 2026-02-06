# frozen_string_literal: true

module UploadDND
  module Generators
    class PolicyGenerator < Rails::Generators::Base
      source_root File.expand_path('templates', __dir__)

      desc "Generate Pundit policies for UploadDND (temporary + permanent attachments)"

      def create_temporary_attachment_policy
        template "policies/upload_d_n_d_temporary_attachment_policy.rb",
                 "app/policies/upload_d_n_d_temporary_attachment_policy.rb"
      end

      def create_attachment_policy
        template "policies/upload_d_n_d_attachment_policy.rb",
                 "app/policies/upload_d_n_d_attachment_policy.rb"
      end

      def show_readme
        readme "POLICY_README" if behavior == :invoke
      end
    end
  end
end
