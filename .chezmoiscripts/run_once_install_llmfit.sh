#!/bin/bash
# Check if profile is personal by inspecting Ansible cache
if grep -q '"dotfiles_profile": "personal"' ~/.ansible/fact_cache/localhost 2>/dev/null || [ "$profile" = "personal" ]; then
    if command -v brew &> /dev/null; then
        brew install AlexsJones/llmfit/llmfit || brew install llmfit
    else
        curl -fsSL https://llmfit.axjns.dev/install.sh | sh
    fi
fi

