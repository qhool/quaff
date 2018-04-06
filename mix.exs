defmodule Quaff.Mixfile do
  use Mix.Project

  def project do
    [
      app: :quaff,
      elixir: "~> 1.6",
      version: "0.1.1",
      deps: deps(Mix.env()),
      description:
        "Quaff is a set of tools for integrating Elixir into erlang applications (or vice versa).",
      package: package(),
      source_url: "https://github.com/aruki-delivery/quaff",
      homepage_url: "https://hex.pm/packages/quaff"
    ]
  end

  def application do
    []
  end

  defp deps(:test) do
    [{:meck, "~> 0.8.9"}] ++ deps(:prod)
  end

  defp deps(_) do
    [{:aleppo, "~> 0.9.0"}, {:ex_doc, ">= 0.0.0", only: :dev}]
  end

  def package do
    [
      maintainers: ["cblage"],
      licenses: ["Apache License 2.0"],
      links: %{"GitHub" => "https://github.com/aruki-delivery/quaff"}
    ]
  end
end
