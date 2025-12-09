class GhCommitAi < Formula
  desc "AI-powered git commit message generator for GitHub CLI"
  homepage "https://github.com/nathanaelphilip/gh-commit-ai"
  url "https://github.com/nathanaelphilip/gh-commit-ai/archive/refs/tags/v1.0.0.tar.gz"
  sha256 "" # Will be filled after first release
  license "MIT"
  version "1.0.0"

  depends_on "gh"

  def install
    bin.install "gh-commit-ai"

    # Install man page
    man1.install "man/gh-commit-ai.1"

    # Install completion scripts
    bash_completion.install "completions/gh-commit-ai.bash" => "gh-commit-ai"
    zsh_completion.install "completions/_gh-commit-ai"

    # Install example config
    (share/"gh-commit-ai").install ".gh-commit-ai.example.yml"
  end

  def caveats
    <<~EOS
      gh-commit-ai has been installed!

      Installation Options:

      1. Install as a gh extension (recommended):
         gh extension install nathanaelphilip/gh-commit-ai

         Then use: gh commit-ai

      2. Use directly from PATH:
         The gh-commit-ai command is now in your PATH.

         Use: gh-commit-ai

      3. Shell completion:
         Bash completion is installed to: #{bash_completion}/gh-commit-ai
         Zsh completion is installed to: #{zsh_completion}/_gh-commit-ai

         Or run: gh-commit-ai install-completion

      4. Man page:
         View documentation with: man gh-commit-ai

      Setup:
      - Copy example config: cp #{share}/gh-commit-ai/.gh-commit-ai.example.yml ~/.gh-commit-ai.yml
      - Choose AI provider:
        • Ollama (free, local): https://ollama.ai
        • Groq (fast, free tier): export GROQ_API_KEY="gsk-..."
        • Anthropic: export ANTHROPIC_API_KEY="sk-ant-..."
        • OpenAI: export OPENAI_API_KEY="sk-proj-..."

      Documentation: https://github.com/nathanaelphilip/gh-commit-ai
    EOS
  end

  test do
    # Test that the script is executable
    assert_match "gh-commit-ai - AI-powered git commit message generator", shell_output("#{bin}/gh-commit-ai --help")

    # Test version
    assert_match version.to_s, shell_output("#{bin}/gh-commit-ai --version")
  end
end
