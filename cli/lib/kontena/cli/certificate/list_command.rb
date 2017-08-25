require_relative '../services/services_helper'

module Kontena::Cli::Certificate
  class ListCommand < Kontena::Command
    include Kontena::Cli::Common
    include Kontena::Cli::GridOptions
    include Kontena::Cli::TableGenerator::Helper

    requires_current_master
    requires_current_master_token
    requires_current_grid

    SEVEN_DAYS = 7 * 24 * 60 * 60
    THREE_DAYS = 3 * 24 * 60 * 60

    def fields
      quiet? ? ['subject'] : {subject: 'subject', "valid until" => 'valid_until'}
    end

    def certificates
      client.get("grids/#{current_grid}/certificates")['certificates']
    end

    def status_icon(row)
      icon = '⊛'.freeze
      valid_until = Time.parse(row['valid_until'])

      if valid_until < (Time.now + THREE_DAYS)
        icon.colorize(:red)
      elsif valid_until < (Time.now + SEVEN_DAYS)
        icon.colorize(:yellow)
      else
        icon.colorize(:green)
      end

    end

    def status_color(row)
      valid_until = Time.parse(row['valid_until'])

      if valid_until < (Time.now + THREE_DAYS)
        :red
      elsif valid_until < (Time.now + SEVEN_DAYS)
        :yellow
      else
        :green
      end

    end

    def execute
      print_table(certificates) do |row|
        #row['subject'] = status_icon(row) + " " + row['subject'] unless quiet?
        row['valid_until'] = row['valid_until'].colorize(status_color(row))
      end
    end
  end
end
