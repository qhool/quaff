defmodule Quaff.Mixfile do
  use Mix.Project

  def project do
    [ app: :quaff,
      version: "0.0.1",
      deps: deps,
    ]
  end

  def application do
    []
  end

  defp deps do
    [ { :aleppo, compile: "rebar compile",
        git: "https://github.com/ChicagoBoss/aleppo.git", branch: "master" },
      { :meck,  git: "https://github.com/eproxus/meck.git", branch: "master" }
    ]
  end
end