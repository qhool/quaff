defmodule Quaff_013.Mixfile do
  use Mix.Project


  def project do
    elixirc_defaults = [debug_info: true, ignore_module_conflict: true, docs: true]
    [
      app: :quaff,
      elixir: "~> 1.6",
      version: "0.1.3",
      deps: deps(Mix.env()),
      elixirc_options: elixirc_defaults ++ options(Mix.env()),
      dialyzer: [paths: ["_build/shared/lib/mqttex/ebin"]],
      description:
        "Quaff is a set of tools for integrating Elixir into erlang applications (or vice versa).",
      package: package(),
      source_url: "https://github.com/aruki-delivery/quaff",
      homepage_url: "https://hex.pm/packages/quaff",
      docs: [readme: true],
    ]
  end

  defp options(env) when env in [:dev, :test], do: [exlager_level: :debug, exlager_truncation_size: 8096]
  defp options(_), do: []


  def application do
    []
  end

  def deps(:prod), do: aleppo()
  def deps(env) when env in [:dev, :test, :docs], do: ex_doc() ++ inch_ex() ++ credo() ++ aleppo() ++ meck()

  defp aleppo, do: [{:aleppo, "~> 0.9.0"}]
  defp credo, do: [{:credo, github: "cblage/credo", branch: "master", only: [:dev, :test], runtime: false}]
  defp inch_ex, do: [{:inch_ex, github: "cblage/inch_ex", branch: "master", only: [:dev, :test], runtime: false}]
  defp ex_doc, do: [{:ex_doc, "~> 0.16", only: :dev, runtime: false}]
  defp meck, do: [{:meck, "~> 0.8.9"}]

  def package do
    [
      maintainers: ["cblage"],
      licenses: ["Apache License 2.0"],
      links: %{"GitHub" => "https://github.com/aruki-delivery/quaff"}
    ]
  end
end
