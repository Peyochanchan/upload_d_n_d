# frozen_string_literal: true

module UploadDND
  module RateLimiting
    extend ActiveSupport::Concern

    included do
      before_action :check_rate_limit, if: :rate_limiting_enabled?
    end

    private

    def rate_limiting_enabled?
      UploadDND.configuration.rate_limit_enabled
    end

    def check_rate_limit
      # Clé basée sur l'IP et l'utilisateur si disponible
      key = rate_limit_key

      # Récupère le compteur actuel pour cette clé
      count = increment_rate_limit_counter(key)

      max_requests = UploadDND.configuration.rate_limit_max_requests
      period = UploadDND.configuration.rate_limit_period

      if count > max_requests
        Rails.logger.warn "UploadDND RateLimit: #{key} exceeded limit (#{count}/#{max_requests})"

        # Calcule le temps restant avant reset
        retry_after = rate_limit_reset_time(key)

        response.headers["Retry-After"] = retry_after.to_s
        response.headers["X-RateLimit-Limit"] = max_requests.to_s
        response.headers["X-RateLimit-Remaining"] = "0"
        response.headers["X-RateLimit-Reset"] = (Time.current + retry_after.seconds).to_i.to_s

        render_error(
          I18n.t("upload_d_n_d.errors.rate_limited", seconds: retry_after),
          :too_many_requests
        )

        false # Stop processing
      else
        # Ajoute les headers informatifs
        response.headers["X-RateLimit-Limit"] = max_requests.to_s
        response.headers["X-RateLimit-Remaining"] = (max_requests - count).to_s
        response.headers["X-RateLimit-Reset"] = (Time.current + period.seconds).to_i.to_s

        true # Continue processing
      end
    end

    def rate_limit_key
      # Combine IP et user_id si disponible pour éviter le partage de limite
      ip = request.remote_ip
      user_identifier = current_user&.id || "anonymous"

      "upload_dnd:rate_limit:#{user_identifier}:#{ip}"
    end

    def increment_rate_limit_counter(key)
      period = UploadDND.configuration.rate_limit_period

      # Lit le compteur actuel ou initialise à 0
      count = Rails.cache.read(key) || 0

      # Incrémente le compteur
      count += 1

      # Écrit le nouveau compteur avec expiration
      Rails.cache.write(key, count, expires_in: period.seconds)

      count
    end

    def rate_limit_reset_time(key)
      # Récupère le TTL du cache pour cette clé
      # Si le cache ne supporte pas ttl, retourne la période par défaut
      period = UploadDND.configuration.rate_limit_period

      begin
        # Certains cache stores supportent `ttl` (Redis, Memcached)
        ttl = Rails.cache.instance_variable_get(:@data)&.ttl(key)
        ttl && ttl > 0 ? ttl : period
      rescue
        period
      end
    end
  end
end
