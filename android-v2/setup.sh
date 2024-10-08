#!/bin/sh

export INSTALLUSER=user1
export NVM_DIR=/home/$INSTALLUSER/.nvm
export NODE_VERSION=18.20.4
export NODE_PATH=$NVM_DIR/v${NODE_VERSION}/lib/node_modules
export FLUTTER_DEFAULT_VERSION=3.22.2
export ANDROID_PLATFORM_VER=33
export ANDROID_BUILD_TOOL_VER=33.0.3
export ANDROID_HOME=/opt/android/sdk
export ANDROID_SDK="${ANDROID_HOME}"
export ANDROID_SDK_ROOT="${ANDROID_HOME}"
export ANDROID_PREFS_ROOT="${ANDROID_HOME}"


set_variables() {
  ## NODEJS
  PATH=${PATH}:${NVM_DIR}/versions/node/v${NODE_VERSION}/bin

  ## ANDROID
  PATH="${PATH}:${ANDROID_HOME}/cmdline-tools/latest/bin"
  PATH="${PATH}:${ANDROID_HOME}/platform-tools"
  PATH="${PATH}:${ANDROID_HOME}/build-tools/${ANDROID_BUILD_TOOL_VER}"
  PATH="${PATH}:${ANDROID_HOME}/ndk-bundle"
  PATH="${PATH}:${ANDROID_HOME}/cmake/3.18.1/bin"

  echo "\n\
export ANDROID_PLATFORM_VER=${ANDROID_PLATFORM_VER}\n\
export ANDROID_BUILD_TOOL_VER=${ANDROID_BUILD_TOOL_VER}\n\
export ANDROID_HOME=${ANDROID_HOME}\n\
export ANDROID_SDK=${ANDROID_HOME}\n\
export ANDROID_SDK_ROOT=${ANDROID_HOME}\n\
export ANDROID_PREFS_ROOT=${ANDROID_HOME}\n\
" >> /etc/profile.d/common.sh

  ## AWS CLI
  PATH="${PATH}:/home/$INSTALLUSER/aws-cli/bin"

  echo "export PATH=\"$PATH\"" >> /etc/profile.d/common.sh

  su - $INSTALLUSER shell -c "mkdir -p /opt/currfs/_rootfs/opt/android /opt/currfs/_rootfs/opt/data /opt/currfs/_rootfs/opt/flutter"
  ln -s /opt/currfs/_rootfs/opt/android /opt/android
  ln -s /opt/currfs/_rootfs/opt/data /opt/data
  ln -s /opt/currfs/_rootfs/opt/flutter /opt/flutter
  chown $INSTALLUSER:$INSTALLUSER /opt/android
  chown $INSTALLUSER:$INSTALLUSER /opt/data
  chown $INSTALLUSER:$INSTALLUSER /opt/flutter
}


install_java() {
  apt update
  apt upgrade -y

  #  chromium-browser \  # for website monitoring
  #  python3 python3-pip \  # for aws-cli
  #  libicu70 tzdata \  # for github actions runner
  #  build-essential  # for building some react native packages
  DEBIAN_FRONTEND=noninteractive apt -y --no-install-recommends install unzip zip curl ca-certificates \
    git openjdk-17-jdk gnupg openssh-client procps \
    chromium-browser \
    python3 python3-pip \
    libicu70 tzdata \
    build-essential
}


install_android_sdk() {
  ADD_EMULATOR=0

  # Version 30.7.2 - latest as at 1 June 2021
  # https://dl.google.com/android/repository/emulator-darwin_x64-7395805.zip
  # https://dl.google.com/android/repository/emulator-linux_x64-7395805.zip
  # https://dl.google.com/android/repository/emulator-windows_x64-7395805.zip
  # CMDTOOLS_FILE=commandlinetools-linux-8512546_latest.zip
  CMDTOOLS_FILE=commandlinetools-linux-9477386_latest.zip
  EMULATOR_FILE=emulator-linux_x64-7395805.zip

  # change to sdkmanager for linux/mac or sdkmanager.bat for windows same for avdmanager
  SDKMAN=sdkmanager
  AVDMAN=avdmanager
  BASE_URL=https://dl.google.com/android/repository
  PREFIX=~

  # Download the minimum required file
  curl -o $PREFIX/$CMDTOOLS_FILE $BASE_URL/$CMDTOOLS_FILE
  mkdir -p $ANDROID_SDK/cmdline-tools
  unzip $PREFIX/$CMDTOOLS_FILE -d $ANDROID_SDK/cmdline-tools
  mv $ANDROID_SDK/cmdline-tools/cmdline-tools $ANDROID_SDK/cmdline-tools/latest
  rm -f $PREFIX/$CMDTOOLS_FILE

  # optional emulator 
  if [ "$ADD_EMULATOR" = "1" ]; then
    curl -o $PREFIX/$EMULATOR_FILE $BASE_URL/$EMULATOR_FILE
    unzip $PREFIX/$EMULATOR_FILE -d $ANDROID_SDK
    cp package.xml $ANDROID_SDK/emulator
    rm -f $PREFIX/$EMULATOR_FILE
    EMULATOR_PKG=emulator
  fi

  # Install the minimum set of tools to compile an Android app
  # patcher:v4 and tools will be automatically installed
  yes | $SDKMAN platform-tools "platforms;android-$ANDROID_PLATFORM_VER" "build-tools;$ANDROID_BUILD_TOOL_VER" \
    "ndk;27.1.12297006" "cmake;3.18.1" $EMULATOR_PKG
}

install_nvm() {
# export NVM_DIR=~/.nvm
# export NODE_VERSION=18.15.0
# export NODE_PATH=$NVM_DIR/v$NODE_VERSION/lib/node_modules
# export PATH=$NVM_DIR/v$NODE_VERSION/bin:$PATH

  cd ~/
# Install nvm with node and npm
  curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.3/install.sh | bash \
    && . $NVM_DIR/nvm.sh \
    && nvm install $NODE_VERSION \
    && nvm alias default $NODE_VERSION \
    && nvm use default
}


install_aws_cli() {
  # Installs the AWS command line tool if it does not exist
  cd ~/

  which aws
  if [ ! "$?" = "0" ]; then
    curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
    unzip awscliv2.zip
    ./aws/install -i ~/aws-cli -b ~/aws-cli/bin
    export PATH=$PATH:~/aws-cli/bin
  fi
}


install_flutter() {
  FLUTTER_VERSION=$1
  if [ "$FLUTTER_VERSION" = "" ]; then echo "Need version" ; exit 1 ; fi

  if [ -d "/opt/flutter/$FLUTTER_VERSION" ]; then
    echo "Flutter $FLUTTER_VERSION already exists at /opt/flutter/$FLUTTER_VERSION"
    exit 1
  fi

  mkdir -p /opt/flutter/$FLUTTER_VERSION
  git clone --single-branch --branch $FLUTTER_VERSION --depth 1 https://github.com/flutter/flutter.git /opt/flutter/$FLUTTER_VERSION
  /opt/flutter/$FLUTTER_VERSION/bin/flutter precache --android
}


install_gh_runner() {
  GHA_VERSION="2.319.1"
  if [ "$(id -u)" = "0" ]; then echo "Do not install Github actions runner as root"; exit 255 ; fi

  cd /opt/data
  mkdir actions-runner && cd actions-runner
  curl -o actions-runner-linux-x64-$GHA_VERSION.tar.gz -L https://github.com/actions/runner/releases/download/v$GHA_VERSION/actions-runner-linux-x64-$GHA_VERSION.tar.gz
  tar xzf ./actions-runner-linux-x64-$GHA_VERSION.tar.gz
}


map_docker_group() {
  if [ "$1" = "" ]; then
    echo "Need a groupd id number"
    exit 255
  fi
  groupadd -g $1 dockerhost
  adduser $INSTALLUSER dockerhost
}

app_start() {
  if [ ! -f /opt/data/actions-runner/.credentials ]; then
    echo "Runner not configured, running shell"
    /bin/sh
  else
    echo "Running github runner"
    # map_docker_group 111
    su - $INSTALLUSER /opt/data/actions-runner/run.sh
  fi
}

# run these two as root
if [ "$1" = "install-java" ]; then install_java; exit; fi
if [ "$1" = "set-vars" ]; then set_variables; exit; fi

# run all these as the $INSTALLUSER
if [ "$1" = "install-sdk" ]; then install_android_sdk; exit; fi
if [ "$1" = "install-nvm" ]; then install_nvm; exit; fi
if [ "$1" = "install-aws-cli" ]; then install_aws_cli; exit; fi
if [ "$1" = "install-flutter" ]; then install_flutter $2 ; exit; fi
if [ "$1" = "install-gh" ]; then install_gh_runner; exit; fi
if [ "$1" = "map-docker" ]; then map_docker_group $2; exit; fi

if [ "$1" = "install-all" ]; then
  set_variables
  install_java
  su - $INSTALLUSER /opt/currfs/setup.sh install-nvm
  su - $INSTALLUSER /opt/currfs/setup.sh install-aws-cli
  su - $INSTALLUSER /opt/currfs/setup.sh install-gh
  su - $INSTALLUSER /opt/currfs/setup.sh install-sdk
  su - $INSTALLUSER /opt/currfs/setup.sh install-flutter $FLUTTER_DEFAULT_VERSION
fi

if [ "$1" = "start" ]; then app_start; exit; fi
