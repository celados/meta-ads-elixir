defmodule MetaAds.TestLocalHTTPServer do
  @moduledoc false

  def serve_once(response) when is_binary(response) do
    {:ok, listener} =
      :gen_tcp.listen(0, [:binary, active: false, ip: {127, 0, 0, 1}, reuseaddr: true])

    {:ok, {_address, port}} = :inet.sockname(listener)

    task =
      Task.async(fn ->
        {:ok, socket} = :gen_tcp.accept(listener)
        request = read_request(socket)
        :ok = :gen_tcp.send(socket, response)
        :ok = :gen_tcp.close(socket)
        :ok = :gen_tcp.close(listener)
        request
      end)

    {"http://127.0.0.1:#{port}", task}
  end

  def await_request(task), do: Task.await(task, 1_000)

  defp read_request(socket, buffer \\ "") do
    case split_request(buffer) do
      {:ok, request} ->
        request

      :more ->
        {:ok, chunk} = :gen_tcp.recv(socket, 0, 1_000)
        read_request(socket, buffer <> chunk)
    end
  end

  defp split_request(buffer) do
    case :binary.split(buffer, "\r\n\r\n") do
      [headers, body] ->
        content_length =
          case Regex.run(~r/^content-length:\s*(\d+)\s*$/im, headers, capture: :all_but_first) do
            [length] -> String.to_integer(length)
            nil -> 0
          end

        if byte_size(body) >= content_length do
          {:ok, headers <> "\r\n\r\n" <> binary_part(body, 0, content_length)}
        else
          :more
        end

      [_incomplete] ->
        :more
    end
  end
end
