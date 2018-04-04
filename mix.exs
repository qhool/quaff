defmodule Quaff.Mixfile do
  use Mix.Project

  def project do
    [
      app: :quaff,
      elixir: "~> 1.6",
      version: "0.0.2",
      deps: deps(Mix.env)
    ]
  end

  def application do
    []
  end

  defp deps(:test) do
    [{:meck, "~> 0.8.9"}] ++ deps(:prod)
  end

  defp deps(_) do
    [{:aleppo, "~> 0.9.0"}]
  end
end
