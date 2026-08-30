defmodule Mix.MetaAds.Snapshot do
  @moduledoc false

  @manifest "priv/codegen/MANIFEST.sha256"
  @source "priv/codegen/SOURCE.json"
  @specs "priv/codegen/specs"

  @spec verify_local!(String.t()) :: :ok
  def verify_local!(project_root \\ File.cwd!()) do
    expected = read_manifest!(Path.join(project_root, @manifest))
    actual = local_snapshot!(Path.join(project_root, @specs))

    case compare_snapshots(expected, actual) do
      :ok -> :ok
      {:error, message} -> Mix.raise("Vendored schema manifest mismatch: #{message}")
    end
  end

  @spec verify_upstream!(String.t()) :: :ok
  def verify_upstream!(project_root \\ File.cwd!()) do
    source = read_source!(Path.join(project_root, @source))
    local = local_contents!(Path.join(project_root, @specs))
    upstream = fetch_upstream!(source)

    case compare_snapshots(local, upstream) do
      :ok -> :ok
      {:error, message} -> Mix.raise("Vendored schema differs from upstream: #{message}")
    end
  end

  @spec write_manifest!(String.t()) :: :ok
  def write_manifest!(project_root \\ File.cwd!()) do
    content =
      project_root
      |> Path.join(@specs)
      |> local_snapshot!()
      |> Enum.map_join("\n", fn {path, digest} -> "#{digest}  #{path}" end)
      |> Kernel.<>("\n")

    File.write!(Path.join(project_root, @manifest), content)
  end

  defp read_source!(path) do
    with {:ok, source} when is_map(source) <- path |> File.read!() |> JSON.decode(),
         repository when is_binary(repository) <- source["repository"],
         commit when is_binary(commit) <- source["commit"],
         source_path when is_binary(source_path) <- source["path"] do
      %{"repository" => repository, "commit" => commit, "path" => source_path}
    else
      _error -> Mix.raise("Invalid schema source metadata: #{path}")
    end
  end

  defp read_manifest!(path) do
    path
    |> File.read!()
    |> String.split("\n", trim: true)
    |> Enum.map(fn line ->
      case String.split(line, "  ", parts: 2) do
        [digest, relative_path] when byte_size(digest) == 64 -> {relative_path, digest}
        _other -> Mix.raise("Invalid schema manifest entry: #{inspect(line)}")
      end
    end)
    |> ensure_unique_paths!()
    |> Enum.sort()
  end

  defp ensure_unique_paths!(entries) do
    paths = Enum.map(entries, &elem(&1, 0))

    if length(paths) == MapSet.size(MapSet.new(paths)) do
      entries
    else
      Mix.raise("Schema manifest contains duplicate paths")
    end
  end

  defp local_snapshot!(specs_path) do
    Enum.map(local_contents!(specs_path), fn {path, content} ->
      {path, sha256(content)}
    end)
  end

  defp local_contents!(specs_path) do
    specs_path
    |> Path.join("**/*")
    |> Path.wildcard(match_dot: true)
    |> Enum.filter(&File.regular?/1)
    |> Enum.map(&{Path.relative_to(&1, specs_path), File.read!(&1)})
    |> Enum.sort()
  end

  defp fetch_upstream!(source) do
    {owner, repository} = github_repository!(source["repository"])

    url =
      "https://codeload.github.com/#{owner}/#{repository}/tar.gz/#{source["commit"]}"

    {:ok, _started} = Application.ensure_all_started(:inets)
    {:ok, _started} = Application.ensure_all_started(:ssl)

    request = {String.to_charlist(url), []}

    http_options = [
      autoredirect: false,
      timeout: 60_000,
      connect_timeout: 15_000,
      ssl: :httpc.ssl_verify_host_options(true)
    ]

    archive =
      case :httpc.request(:get, request, http_options, body_format: :binary) do
        {:ok, {{_version, 200, _phrase}, _headers, body}} ->
          body

        {:ok, {{_version, status, _phrase}, _headers, _body}} ->
          Mix.raise("Upstream schema ref is unreachable: HTTP #{status} for #{url}")

        {:error, reason} ->
          Mix.raise("Upstream schema ref is unreachable: #{inspect(reason)}")
      end

    entries =
      case :erl_tar.extract({:binary, archive}, [:compressed, :memory]) do
        {:ok, entries} ->
          entries

        {:error, reason} ->
          Mix.raise("Unable to read upstream schema archive: #{inspect(reason)}")
      end

    prefix = String.trim(source["path"], "/") <> "/"

    entries
    |> Enum.flat_map(fn {path, content} ->
      case path |> List.to_string() |> String.split("/", parts: 2) do
        [_archive_root, relative_path] ->
          if String.starts_with?(relative_path, prefix) do
            [{String.replace_prefix(relative_path, prefix, ""), content}]
          else
            []
          end

        _other ->
          []
      end
    end)
    |> Enum.reject(fn {path, _content} -> path == "" end)
    |> Enum.sort()
  end

  defp github_repository!(repository_url) do
    uri = URI.parse(repository_url)

    case {uri.scheme, uri.host, String.split(String.trim(uri.path || "", "/"), "/")} do
      {"https", "github.com", [owner, repository]} ->
        {owner, String.trim_trailing(repository, ".git")}

      _other ->
        Mix.raise("Schema repository must be an HTTPS github.com owner/repository URL")
    end
  end

  defp compare_snapshots(expected, actual) do
    expected_map = Map.new(expected)
    actual_map = Map.new(actual)

    missing =
      expected_map |> Map.keys() |> Enum.reject(&Map.has_key?(actual_map, &1)) |> Enum.sort()

    extra =
      actual_map |> Map.keys() |> Enum.reject(&Map.has_key?(expected_map, &1)) |> Enum.sort()

    changed =
      expected_map
      |> Map.keys()
      |> Enum.filter(&(Map.has_key?(actual_map, &1) and expected_map[&1] != actual_map[&1]))
      |> Enum.sort()

    if missing == [] and extra == [] and changed == [] do
      :ok
    else
      {:error,
       "missing=#{inspect(missing)}, extra=#{inspect(extra)}, changed=#{inspect(changed)}"}
    end
  end

  defp sha256(content) do
    :crypto.hash(:sha256, content)
    |> Base.encode16(case: :lower)
  end
end
