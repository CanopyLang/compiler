class Canopy < Formula
  desc "A delightful language for reliable web applications"
  homepage "https://canopy-lang.org"
  version "0.19.1"
  license "BSD-3-Clause"

  on_macos do
    on_arm do
      url "https://github.com/canopy-lang/canopy/releases/download/v#{version}/canopy-#{version}-darwin-aarch64.tar.gz"
      sha256 "PLACEHOLDER_DARWIN_AARCH64_SHA256"
    end
    on_intel do
      url "https://github.com/canopy-lang/canopy/releases/download/v#{version}/canopy-#{version}-darwin-x86_64.tar.gz"
      sha256 "PLACEHOLDER_DARWIN_X86_64_SHA256"
    end
  end

  on_linux do
    on_intel do
      url "https://github.com/canopy-lang/canopy/releases/download/v#{version}/canopy-#{version}-linux-x86_64.tar.gz"
      sha256 "PLACEHOLDER_LINUX_X86_64_SHA256"
    end
  end

  def install
    bin.install "canopy"
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/canopy --version")
  end
end
