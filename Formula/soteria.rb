# Homebrew formula for soteria.
#   brew install https://raw.githubusercontent.com/koushiksaravanan/soteria/v0/Formula/soteria.rb
class Soteria < Formula
  desc "Supervisor layer for coding agents"
  homepage "https://github.com/koushiksaravanan/soteria"
  url "https://github.com/koushiksaravanan/soteria/archive/refs/tags/v0.tar.gz"
  sha256 "7aad5d998dfb35a8126d09deb3cca0996eacebb6613fa9391f7c476a4c6e12ff"
  license "MIT"
  depends_on "python@3.12"

  def install
    # Keep script + resources side by side: the CLI resolves profiles/ui
    # relative to argv[0], and shims re-enter via absolute path.
    libexec.install "soteria", "profiles", "ui"
    (bin/"soteria").write_env_script libexec/"soteria",
      PATH: "#{Formula["python@3.12"].opt_bin}:${PATH}"
  end

  test do
    system bin/"soteria", "setup", "--check-only"
    system bin/"soteria", "profile", "list"
  end
end
