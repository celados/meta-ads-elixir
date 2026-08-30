defmodule MetaAds.GeneratorTest do
  use ExUnit.Case, async: false

  test "keeps the existing generated tree when a schema is invalid" do
    root =
      Path.join(
        System.tmp_dir!(),
        "meta_ads_generator_#{System.unique_integer([:positive, :monotonic])}"
      )

    on_exit(fn -> File.rm_rf!(root) end)

    specs = Path.join(root, "specs")
    output = Path.join(root, "lib/meta_ads/models")
    File.mkdir_p!(specs)
    File.mkdir_p!(output)
    File.write!(Path.join(root, "mix.exs"), "# generator fixture\n")
    File.write!(Path.join(output, "existing.ex"), "existing generated source\n")
    File.write!(Path.join(specs, "a_valid.json"), ~s({"fields":[],"apis":[]}))
    File.write!(Path.join(specs, "z_invalid.json"), "{")

    assert_raise Mix.Error, fn ->
      File.cd!(root, fn -> Mix.Tasks.MetaAds.Generate.run(["--specs", specs]) end)
    end

    assert File.read!(Path.join(output, "existing.ex")) == "existing generated source\n"
    refute File.exists?(Path.join(output, "a_valid.ex"))
  end
end
