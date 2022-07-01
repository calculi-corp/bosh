require 'bosh/director/api/controllers/base_controller'

module Bosh::Director
  module Api::Controllers
    class PackagesController < BaseController
      post '/matches', :consumes => :yaml do
        manifest = YAML.load(request.body.read, aliases: true)

        unless manifest.is_a?(Hash) && manifest['packages'].is_a?(Array)
          raise BadManifest, "Manifest doesn't have a usable packages section"
        end

        fingerprint_list = []

        manifest['packages'].each do |package|
          fingerprint_list << package['fingerprint'] if package['fingerprint']
        end

        matching_packages = []

        unless existing_release_version_dirty?(manifest)
          matching_packages = Models::Package.where(fingerprint: fingerprint_list)
                                             .where(Sequel.~(sha1: nil))
                                             .where(Sequel.~(blobstore_id: nil)).all
        end

        json_encode(matching_packages.map(&:fingerprint).compact.uniq)
      end

      post '/matches_compiled', :consumes => :yaml do
        manifest = YAML.load(request.body.read, aliases: true)

        unless manifest.is_a?(Hash) && manifest['compiled_packages'].is_a?(Array)
          raise BadManifest, "Manifest doesn't have a usable packages section"
        end

        fingerprint_list = []
        manifest['compiled_packages'].each do |package|
          fingerprint_list << package['fingerprint'] if package['fingerprint']
        end

        matching_packages = []

        unless existing_release_version_dirty?(manifest)
          matching_packages = Models::Package.join('compiled_packages', package_id: :id)
                                             .select(Sequel.qualify('packages', 'name'),
                                                     Sequel.qualify('packages', 'fingerprint'),
                                                     Sequel.qualify('compiled_packages', 'dependency_key'),
                                                     :stemcell_os,
                                                     :stemcell_version)
                                             .where(fingerprint: fingerprint_list).all

          matching_packages = filter_matching_packages(matching_packages, manifest)
        end

        json_encode(matching_packages.map(&:fingerprint).compact.uniq)
      end

      private

      # dependencies & stemcell should also match
      def filter_matching_packages(matching_packages, manifest)
        compiled_release_manifest = CompiledRelease::Manifest.new(manifest)
        filtered_packages = []
        matching_packages.each do |package|
          if compiled_release_manifest.has_matching_package(package.name, package[:stemcell_os], package[:stemcell_version], package[:dependency_key])
            filtered_packages << package
          end
        end
        filtered_packages
      end

      def existing_release_version_dirty?(manifest)
        release = Models::Release.first(name: manifest['name'])
        release_version = Models::ReleaseVersion.first(release_id: release&.id, version: manifest['version'])

        release_version && !release_version.update_completed
      end
    end
  end
end
