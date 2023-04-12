#!/bin/bash

# SPDX-FileCopyrightText: 2023 Zextras <https://www.zextras.com>
#
# SPDX-License-Identifier: AGPL-3.0-only


build_package()
{
  targetOs=$1
  targetRegistry=$2
  pkgVersion=$3
  stagingPath=$4
  echo "Building package for" "$targetOs"", this may take a while.."
  docker run --rm --entrypoint ""  --mount type=bind,source="$stagingPath",target=/tmp/staging -e VERSION="$pkgVersion" $targetRegistry /bin/bash -c 'cd /tmp/staging/package && pacur build '"$targetOs"
}

install_package()
{
  pkgName=$1
  pkgVer=$2
  pkgRel=$3
  targetOs=$4
  stagingPath=$5
  if [ "$targetOs" = "Rocky" ]; then
    pkgExt=".el8.x86_64.rpm"
    targetRegistry=registry.dev.zextras.com/jenkins/pacur/rocky-8:v1
    pkgFullName="$pkgName"-"$pkgVer""-""$pkgRel""$pkgExt"
    install_command='dnf install /tmp/'"$pkgFullName"
  else
    pkgExt="_amd64.deb"
    targetRegistry=registry.dev.zextras.com/jenkins/pacur/ubuntu-20.04:v1
    pkgFullName="$pkgName"_"$pkgVer""-""$pkgRel""$pkgExt"
    install_command='apt install /tmp/'"$pkgFullName"
  fi

  mountPath="$stagingPath/package/$pkgFullName"
  docker run --rm --entrypoint "" --mount type=bind,source="$mountPath",target=/tmp/"$pkgFullName" $targetRegistry bin/bash -c "$install_command"
}

set_package_version()
{
  vers=$1
  rel=$2
  stagingPath=$3
  file="$stagingPath/package/PKGBUILD"

  cat "$file" | sed -e "s/\(pkgver=\).*/\1\"$vers\"/" -e "s/\(pkgrel=\).*/\1\"$rel\"/" > "$(pwd)"/../staging/tempPKG
  mv "$(pwd)"/../staging/tempPKG "$file"
}

ubuntu=false
rocky8=false
install=false
version=1
releases=1
help=false
no_cleanup=false
project_path=$(pwd)
while getopts ruinhv:p: flag
do
    case "${flag}" in
        u) ubuntu=true;;
        r) rocky8=true;;
        i) install=true;;
        v) version=${OPTARG};;
        p) project_path=${OPTARG};;
        h) help=true;;
        n) no_cleanup=true;;
        *) help=true;;
    esac
done

if [ $help = true ]; then
  echo "This script can build and optionally install the the project package in a docker container. Options:
   -r creates the package for rocky8,
   -u creates the package for ubuntu,
   -i installs the packages that have been created in the build phase,
   -n disables cleanup of all the files after execution."
   exit 0
 fi

echo "project path" "$project_path";
echo "ubuntu: $ubuntu";
echo "rocky8: $rocky8";
echo "install": $install;
echo "version: $version";
echo "no cleanup": $no_cleanup

staging_path="$project_path"/../staging

buildUbuntuPackage=1
cp -r "$project_path" "$staging_path"

set_package_version "$version" "$releases" "$staging_path"

if [ $ubuntu = true ]; then
  build_package "ubuntu" registry.dev.zextras.com/jenkins/pacur/ubuntu-20.04:v1 "$version" "$staging_path"
  buildUbuntuPackage=$?
fi

buildRockyPackage=1
if [ $rocky8 = true ]; then
  build_package "rocky" registry.dev.zextras.com/jenkins/pacur/rocky-8:v1 "$version" "$staging_path"
  buildRockyPackage=$?
fi


installUbuntuPackage=1
if [ $buildUbuntuPackage = 0 ]; then
  echo "Ubuntu build completed successfully"
  if [ $install = true ]; then
    echo "Installing package for ubuntu.."
    install_package "carbonio-preview-ce" "$version" "$releases" "Ubuntu" "$staging_path"
    installUbuntuPackage=$?
  fi
fi

installRockyPackage=1
if [ $buildRockyPackage = 0 ]; then
  echo "Rocky build completed successfully"
  if [ $install = true ]; then
    echo "Installing package for rocky8.."
    install_package "carbonio-preview-ce" "$version" "$releases" "Rocky" "$staging_path"
    installRockyPackage=$?
  fi
fi

echo "Summary:
  | OPERATION                 | RESULT
  | Ubuntu  build   required  |" $ubuntu"
  | Rocky   build   required  |" $rocky8"
  | Ubuntu  build   exit code |" $buildUbuntuPackage"
  | Rocky   build   exit code |" $buildRockyPackage"
  | Package install required  |" $install"
  | Ubuntu  install exit code |" $installUbuntuPackage"
  | Rocky   install exit code |" $installRockyPackage

if [ $no_cleanup = false ]; then
  echo "Cleaning up.. "
  rm -rf "$staging_path"
fi
exit 0
