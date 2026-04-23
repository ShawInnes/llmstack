FROM ubuntu

RUN apt-get update \
 && apt-get install -y \
  curl \
  git \
  sudo \
  vim \
  wget \
  python3 \
 && rm -rf /var/lib/apt/lists/*

# Install the latest code-server.
# Append "--version x.x.x" to install a specific version of code-server.
RUN curl -fsSL https://code-server.dev/install.sh | sh -s -- --method=standalone --prefix=/opt/code-server

ARG USER=coder
RUN useradd --groups sudo --no-create-home --shell /bin/bash ${USER} \
 && echo "${USER} ALL=(ALL) NOPASSWD:ALL" >/etc/sudoers.d/${USER} \
 && chmod 0440 /etc/sudoers.d/${USER}

USER ${USER}

WORKDIR /home/${USER}