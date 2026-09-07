# Homebrew formula for soteria. Activates on the v0 push+tag:
#   brew install https://raw.githubusercontent.com/koushiksaravanan/soteria/v0/Formula/soteria.rb
# (Or via a tap. Until then this file is untested — formulas need a real tarball.)
class Soteria < Formula
  desc "Supervisor layer for coding agents"
  homepage "https://github.com/koushiksaravanan/soteria"
  url "https://github.com/koushiksaravanan/soteria/archive/refs/tags/v0.tar.gz"
  sha256 "REPLACE_WITH_V0_TARBALL_SHA256"
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
