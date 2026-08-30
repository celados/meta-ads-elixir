defmodule MetaAds.Error do
  @moduledoc """
  Transport, validation, and Meta Graph API errors.

  Meta's error envelope is retained in `:details` so callers can handle new
  error fields without an SDK release.
  """

  defexception [
    :reason,
    :status,
    :code,
    :subcode,
    :type,
    :fbtrace_id,
    :details,
    :field,
    message: "Meta Ads API request failed"
  ]

  @type t :: %__MODULE__{}

  @spec validation(String.t() | atom(), String.t()) :: t()
  def validation(field, message) when is_atom(field), do: validation(to_string(field), message)

  def validation(field, message) when is_binary(field) do
    %__MODULE__{field: field, message: message}
  end

  @doc "Maps Meta's Graph API error envelope."
  @spec from_response(MetaAds.Response.t()) :: t()
  def from_response(%MetaAds.Response{status: status, body: body}) do
    envelope = if is_map(body), do: Map.get(body, "error", %{}), else: %{}
    envelope = if is_map(envelope), do: envelope, else: %{}

    %__MODULE__{
      status: status,
      code: envelope["code"],
      subcode: envelope["error_subcode"],
      type: envelope["type"],
      fbtrace_id: envelope["fbtrace_id"],
      details: envelope,
      message: envelope["message"] || "Meta Ads API returned HTTP #{status}"
    }
  end

  @spec from_transport(term()) :: t()
  def from_transport(reason) do
    %__MODULE__{reason: reason, message: "Meta Ads API transport failed: #{inspect(reason)}"}
  end

  @impl Exception
  def message(%__MODULE__{message: message}), do: message
end
