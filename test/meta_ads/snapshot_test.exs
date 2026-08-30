defmodule Mix.MetaAds.SnapshotTest do
  use ExUnit.Case, async: true

  test "the vendored schema matches its deterministic manifest" do
    assert :ok = Mix.MetaAds.Snapshot.verify_local!()
  end
end
