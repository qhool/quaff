defmodule Quaff.Mixfile do
  use Mix.Project

  def project do
    [ app: :quaff,
      version: "0.1.0",
      deps: deps(Mix.env)
    ]
  end

  def application do
    application(Mix.env)
  end

  defp application(:test) do
    Keyword.merge(application(:prod),[
          applications: [:eunit, :meck, :inets, :public_key, :snmp]
        ], fn _,a,b -> List.flatten(a,b) end)
  end
  defp application(_) do
    [ applications: [:debugger, :aleppo] ]
  end

  defp deps(:test) do
    [ { :meck,  git: "https://github.com/eproxus/meck.git", branch: "master" } |
        deps(:prod) ]
  end
  defp deps(_) do
    [{:aleppo, git: "https://github.com/ErlyORM/aleppo.git", tag: "v0.9.5"}]
  end

end
