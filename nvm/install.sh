# Check if NVM is already installed
if ! command -v nvm &> /dev/null; then
  echo "Installing NVM."
  curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
else
  echo "NVM is already installed. Skipping installation."
fi

