defmodule MetaAds.MixProject do
  use Mix.Project

  def project do
    [
      app: :meta_ads,
      version: "0.1.0",
      # 1.20 is needed for the built-in JSON codec; -rc keeps local development usable.
      elixir: "~> 1.20.0-rc",
      start_permanent: Mix.env() == :prod,
      description: "Generated Elixir SDK for the Meta Marketing API",
      elixirc_paths: elixirc_paths(Mix.env()),
      elixirc_options: [warnings_as_errors: true],
      package: package(),
      deps: deps(),
      docs: docs()
    ]
  end

  def application do
    # :inets and :ssl are runtime needs of the built-in HTTP adapter.
    [extra_applications: [:logger, :inets, :ssl]]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_env), do: ["lib"]

  defp deps do
    [
      {:ex_doc, "~> 0.37", only: :dev, runtime: false}
    ]
  end

  defp package do
    [
      maintainers: ["Ethan Huo"],
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/ethan-huo/meta-ads-elixir"}
    ]
  end

  defp docs do
    [main: "readme", extras: ["README.md", "docs/architecture.md"]]
  end
end
