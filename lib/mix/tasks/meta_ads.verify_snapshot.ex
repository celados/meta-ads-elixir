defmodule Mix.Tasks.MetaAds.VerifySnapshot do
  use Mix.Task

  @shortdoc "Verifies the vendored schema manifest and upstream source"

  @moduledoc """
  Verifies every vendored schema file against `MANIFEST.sha256` and the exact
  upstream commit recorded in `SOURCE.json`.

      mix meta_ads.verify_snapshot

  After intentionally replacing the pinned snapshot, verify the new upstream
  source before rewriting the deterministic local manifest:

      mix meta_ads.verify_snapshot --update-manifest
  """

  @impl Mix.Task
  def run(args) do
    {options, _argv, invalid} = OptionParser.parse(args, strict: [update_manifest: :boolean])

    if invalid != [] do
      Mix.raise("Unexpected snapshot verification options: #{inspect(invalid)}")
    end

    project_root = File.cwd!()

    if options[:update_manifest] do
      Mix.MetaAds.Snapshot.verify_upstream!(project_root)
      Mix.MetaAds.Snapshot.write_manifest!(project_root)
      Mix.MetaAds.Snapshot.verify_local!(project_root)
    else
      Mix.MetaAds.Snapshot.verify_local!(project_root)
      Mix.MetaAds.Snapshot.verify_upstream!(project_root)
    end

    Mix.shell().info("Verified vendored schema manifest and upstream source")
  end
end
