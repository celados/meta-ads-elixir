defmodule Mix.Tasks.MetaAds.Generate do
  @shortdoc "Regenerates Meta Ads model modules"

  @moduledoc """
  Regenerates `lib/meta_ads/models` from Meta's Business SDK JSON schema.

  The default input is the vendored schema snapshot. Keeping a pinned snapshot
  makes package builds reproducible; updating it is an explicit schema upgrade,
  not a side effect of compilation. Operations with file parameters remain
  omitted until the runtime has a multipart transport contract.
  """

  use Mix.Task

  @default_specs "priv/codegen/specs"
  @output "lib/meta_ads/models"

  @impl Mix.Task
  def run(args) do
    {options, _argv, invalid} = OptionParser.parse(args, strict: [specs: :string])

    if invalid != [] do
      Mix.raise("Unexpected generator options: #{inspect(invalid)}")
    end

    project_root = File.cwd!()
    specs_path = Path.expand(options[:specs] || @default_specs, project_root)
    output_path = Path.join(project_root, @output)

    unless File.exists?(Path.join(project_root, "mix.exs")) do
      Mix.raise("Run this task from the meta_ads project root")
    end

    unless File.dir?(specs_path) do
      Mix.raise("Schema directory does not exist: #{specs_path}")
    end

    if specs_path == Path.join(project_root, @default_specs) do
      Mix.MetaAds.Snapshot.verify_local!(project_root)
    end

    spec_files =
      specs_path
      |> Path.join("*.json")
      |> Path.wildcard()
      |> Enum.sort()

    enum_types = load_enum_types(specs_path)
    model_files = Enum.reject(spec_files, &String.ends_with?(&1, "/enum_types.json"))

    # The output is a derived, project-local directory; deleting it keeps stale
    # modules from surviving a schema contraction.
    File.rm_rf!(output_path)
    File.mkdir_p!(output_path)

    counts =
      Enum.reduce(
        model_files,
        %{models: 0, operations: 0, skipped_dynamic: 0, skipped_file: 0},
        fn path, counts ->
          case JSON.decode(File.read!(path)) do
            {:ok, %{} = spec} ->
              stats = write_model!(output_path, path, spec, enum_types)

              %{
                counts
                | models: counts.models + 1,
                  operations: counts.operations + stats.operations,
                  skipped_dynamic: counts.skipped_dynamic + stats.skipped_dynamic,
                  skipped_file: counts.skipped_file + stats.skipped_file
              }

            {:ok, other} ->
              Mix.raise("Expected an object schema in #{path}, got: #{inspect(other)}")

            {:error, reason} ->
              Mix.raise("Invalid JSON in #{path}: #{inspect(reason)}")
          end
        end
      )

    Mix.shell().info(
      "Generated #{counts.models} models and #{counts.operations} operations; " <>
        "skipped #{counts.skipped_dynamic} dynamic endpoint(s) and " <>
        "#{counts.skipped_file} multipart operation(s)"
    )

    output_path
    |> Path.join("**/*.ex")
    |> Path.wildcard()
    |> then(&Mix.Task.rerun("format", &1))
  end

  defp load_enum_types(specs_path) do
    path = Path.join(specs_path, "enum_types.json")

    if File.exists?(path) do
      case JSON.decode(File.read!(path)) do
        {:ok, enums} when is_list(enums) ->
          Map.new(enums, &{&1["name"], &1["values"]})

        _other ->
          Mix.raise("Invalid enum_types.json schema")
      end
    else
      %{}
    end
  end

  defp write_model!(output_path, path, spec, enum_types) do
    source_name = Path.rootname(Path.basename(path))
    module_name = Macro.camelize(source_name)
    file_name = Macro.underscore(module_name) <> ".ex"

    fields =
      spec
      |> Map.get("fields", [])
      |> Enum.map(fn field ->
        field_name = field["name"]
        type = field["type"]
        values = Map.get(enum_types, type, [])

        "  field #{inspect(field_name)}, #{inspect(type)}, #{literal(values)}"
      end)

    {operation_lines, stats} =
      spec
      |> Map.get("apis", [])
      |> Enum.map_reduce(
        %{operations: 0, skipped_dynamic: 0, skipped_file: 0},
        fn api, stats ->
          endpoint = Map.get(api, "endpoint", "")
          params = Map.get(api, "params", [])

          cond do
            String.contains?(endpoint, "{") ->
              {"", %{stats | skipped_dynamic: stats.skipped_dynamic + 1}}

            Enum.any?(params, &file_param?/1) ->
              # A generated function would otherwise silently form-encode a file path.
              {"", %{stats | skipped_file: stats.skipped_file + 1}}

            true ->
              base_path = Map.get(api, "basePath") || Map.get(api, "base_path")
              params = Enum.map(params, &param_with_values(&1, enum_types))
              # Macro escaping is used instead of inspect/1 because Mix truncates
              # deeply nested inspect output by default, which emits invalid source.
              params_literal = literal(params)

              line =
                "  operation #{inspect(function_name(api, endpoint))}, #{inspect(api["method"])}, " <>
                  "#{inspect(endpoint)}, #{inspect(base_path)}, #{params_literal}"

              {line, %{stats | operations: stats.operations + 1}}
          end
        end
      )

    body =
      [
        "# This file is generated by mix meta_ads.generate; manual edits will be lost.",
        "defmodule MetaAds.Models.#{module_name} do",
        "  use MetaAds.Model"
      ] ++
        ["" | fields] ++
        ["" | operation_lines] ++
        ["  finish()", "end", ""]

    File.write!(Path.join(output_path, file_name), Enum.join(body, "\n"))
    stats
  end

  defp param_with_values(param, enum_types) do
    values = enum_values(param["type"], enum_types)
    if values, do: Map.put(param, "values", values), else: param
  end

  defp literal(term), do: term |> Macro.escape() |> Macro.to_string()

  defp enum_values("list<" <> rest = _type, enum_types) do
    inner_type = String.trim_trailing(rest, ">")
    values = Map.get(enum_types, inner_type)
    if values, do: values, else: nil
  end

  defp enum_values(type, enum_types) do
    Map.get(enum_types, type)
  end

  defp file_param?(%{"type" => "file"}), do: true

  defp file_param?(%{"type" => "list<" <> rest}) do
    if String.ends_with?(rest, ">") do
      rest
      |> String.slice(0, byte_size(rest) - 1)
      |> then(&file_param?(%{"type" => &1}))
    else
      false
    end
  end

  defp file_param?(_param), do: false

  defp function_name(api, endpoint) do
    action =
      case api["method"] do
        "GET" -> "get"
        "POST" -> "create"
        "DELETE" -> "delete"
        "PUT" -> "update"
      end

    suffix =
      endpoint
      |> String.replace(~r/[^0-9A-Za-z_]+/, "_")
      |> String.downcase()
      |> String.trim("_")

    # Root-level custom operations all have an empty endpoint; Meta's generated
    # name is the only stable discriminator once basePath differs.
    suffix =
      case api["name"] do
        "gen" <> named when endpoint == "" ->
          named
          |> Macro.underscore()
          |> String.trim("_")
          |> trim_generated_method(api["method"])

        _ ->
          suffix
      end

    if suffix == "", do: String.to_atom(action), else: String.to_atom(action <> "_" <> suffix)
  end

  defp trim_generated_method(suffix, method) do
    method = String.downcase(method)

    cond do
      suffix == method ->
        ""

      String.starts_with?(suffix, method <> "_") ->
        String.replace_prefix(suffix, method <> "_", "")

      true ->
        suffix
    end
  end
end
