defmodule Quaff.Mixfile do
  use Mix.Project

  def project do
    [ app: :quaff,
      version: "0.0.1",
      deps: deps(Mix.env)
    ]
  end

  def application do
    []
  end

  defp deps(:test) do
    [ { :meck,  git: "https://github.com/eproxus/meck.git", branch: "master" } |
        deps(:prod) ]
  end
  defp deps(_) do
    [ { :aleppo, compile: "rebar compile",
        git: "https://github.com/ChicagoBoss/aleppo.git", branch: "master" },
    ]
  end
end