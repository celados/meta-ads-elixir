defmodule MetaAds.Model do
  @moduledoc false

  alias MetaAds.{Client, Params, Response}

  defmacro __using__(_opts) do
    quote do
      import MetaAds.Model, only: [field: 3, operation: 5, finish: 0]
    end
  end

  defmacro field(name, type, values \\ []) do
    {values, _binding} = Code.eval_quoted(values, [], __CALLER__)
    field = %{"name" => name, "type" => type, "values" => values}
    caller = __CALLER__

    Module.put_attribute(caller.module, :meta_ads_fields, [
      field | Module.get_attribute(caller.module, :meta_ads_fields, [])
    ])

    :ok
  end

  defmacro operation(function_name, method, endpoint, base_path, params) do
    doc_text = "Generated Graph API operation #{method} #{endpoint}"
    {params, _binding} = Code.eval_quoted(params, [], __CALLER__)

    operation = %{
      "function" => to_string(function_name),
      "method" => method,
      "endpoint" => endpoint,
      "basePath" => base_path,
      "params" => params
    }

    caller = __CALLER__

    Module.put_attribute(
      caller.module,
      :meta_ads_operations,
      [operation | Module.get_attribute(caller.module, :meta_ads_operations, [])]
    )

    quote do
      @doc unquote(doc_text)
      @spec unquote(function_name)(MetaAds.Client.t(), String.t(), map() | keyword(), keyword()) ::
              {:ok, MetaAds.Response.t()} | {:error, MetaAds.Error.t()}
      def unquote(function_name)(client, object_id, params \\ %{}, options \\ []) do
        MetaAds.Model.request(
          __MODULE__,
          unquote(method),
          unquote(endpoint),
          unquote(base_path),
          unquote(Macro.escape(params)),
          client,
          object_id,
          params,
          options
        )
      end
    end
  end

  defmacro finish do
    caller = __CALLER__
    fields = caller.module |> Module.get_attribute(:meta_ads_fields, []) |> Enum.reverse()
    operations = caller.module |> Module.get_attribute(:meta_ads_operations, []) |> Enum.reverse()

    quote do
      @meta_ads_fields unquote(Macro.escape(fields))
      @meta_ads_operations unquote(Macro.escape(operations))

      @doc "Returns this model's generated Graph API schema fragment."
      @spec __schema__() :: %{optional(String.t()) => term()}
      def __schema__ do
        %{"fields" => @meta_ads_fields, "operations" => @meta_ads_operations}
      end

      @doc "Returns generated field metadata."
      @spec fields() :: list(map())
      def fields, do: @meta_ads_fields

      @doc "Returns generated operation metadata."
      @spec operations() :: list(map())
      def operations, do: @meta_ads_operations
    end
  end

  @spec request(
          module(),
          String.t(),
          String.t(),
          String.t() | nil,
          list(map()),
          Client.t(),
          String.t(),
          map() | keyword(),
          keyword()
        ) ::
          {:ok, Response.t()} | {:error, MetaAds.Error.t()}
  def request(
        _model,
        method,
        endpoint,
        base_path,
        spec_params,
        %Client{} = client,
        object_id,
        params,
        options
      ) do
    with {:ok, validated} <- Params.validate(params, spec_params) do
      Client.request(
        client,
        normalize_method(method),
        Client.path(client, object_id, endpoint, base_path),
        validated,
        options
      )
    end
  end

  defp normalize_method("GET"), do: :get
  defp normalize_method("POST"), do: :post
  defp normalize_method("PUT"), do: :put
  defp normalize_method("DELETE"), do: :delete
end
