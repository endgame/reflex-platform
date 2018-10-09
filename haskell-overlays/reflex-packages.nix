{ haskellLib
, lib, nixpkgs
, fetchFromGitHub, hackGet
, useFastWeak, useReflexOptimizer, enableTraceReflexEvents, enableLibraryProfiling
}:

with haskellLib;

self: super:

let
  reflexDom = import (hackGet ../reflex-dom) self nixpkgs;
  jsaddleSrc = jsaddleDevelopSrc; # hackGet ../jsaddle;
  jsaddleDevelopSrc = fetchFromGitHub {
    owner = "ghcjs";
    repo = "jsaddle";
    rev = "50126cdcc15caeecb5910a15ac6cb67e3ab638ae";
    sha256 = "0pnn36h6a8sfwhhf34px6a1lvzr447p7z0r0ky7shv7d78awfvgc";
  };
  gargoylePkgs = self.callPackage (hackGet ../gargoyle) self;
  ghcjsDom = import (hackGet ../ghcjs-dom) self;
  addReflexTraceEventsFlag = drv: if enableTraceReflexEvents
    then appendConfigureFlag drv "-fdebug-trace-events"
    else drv;
  addReflexOptimizerFlag = drv: if useReflexOptimizer && (self.ghc.cross or null) == null
    then appendConfigureFlag drv "-fuse-reflex-optimizer"
    else drv;
  addFastWeakFlag = drv: if useFastWeak
    then enableCabalFlag drv "fast-weak"
    else drv;
in
{
  ##
  ## Reflex family
  ##

  reflex = dontCheck (addFastWeakFlag (addReflexTraceEventsFlag (addReflexOptimizerFlag (self.callPackage (hackGet ../reflex) {}))));
  reflex-todomvc = self.callPackage (hackGet ../reflex-todomvc) {};
  reflex-aeson-orphans = self.callCabal2nix "reflex-aeson-orphans" (hackGet ../reflex-aeson-orphans) {};

  # Broken Haddock - Please fix!
  # : error is: haddock: internal error: internal: extractDecl
  # No idea where it hits?
  reflex-dom = dontHaddock (addReflexOptimizerFlag reflexDom.reflex-dom);
  reflex-dom-core = appendConfigureFlags
    (dontHaddock (addReflexOptimizerFlag reflexDom.reflex-dom-core))
    (lib.optional enableLibraryProfiling "-fprofile-reflex");

  ##
  ## GHCJS and JSaddle
  ##

  jsaddle = overrideCabal (self.callCabal2nix "jsaddle" "${jsaddleSrc}/jsaddle" {}) (drv: {
    jailbreak = true;
    postPatch = (drv.postPatch or "") + ''
      substituteInPlace "jsaddle.cabal" --replace "http-types >=0.8.6 && <0.12" http-types
      substituteInPlace "src-ghc/Data/JSString/Internal/Type.hs" --replace \
        "newtype JSString = JSString Text deriving(Show, Read, IsString, Monoid, Ord, Eq, Data, ToJSON, FromJSON, Typeable)" \
        "newtype JSString = JSString Text deriving(Show, Read, IsString, Semigroup, Monoid, Ord, Eq, Data, ToJSON, FromJSON, Typeable)"
      substituteInPlace "src/Language/Javascript/JSaddle/Run.hs" --replace \
        "import GHC.Stats (getGCStatsEnabled, getGCStats, GCStats(..))" \
        "import GHC.Stats (getRTSStatsEnabled, getRTSStats, RTSStats(..), gcdetails_live_bytes, gc)" \
        --replace \
        'currentBytesUsedStr <- getGCStatsEnabled >>= \case' 'currentBytesUsedStr <- getRTSStatsEnabled >>= \case' \
        --replace \
        'True  -> show . currentBytesUsed <$> getGCStats' 'True  -> show . gcdetails_live_bytes . gc <$> getRTSStats'
    '';
  });
  jsaddle-clib = self.callCabal2nix "jsaddle-clib" "${jsaddleSrc}/jsaddle-clib" {};
  jsaddle-webkit2gtk = self.callCabal2nix "jsaddle-webkit2gtk" "${jsaddleSrc}/jsaddle-webkit2gtk" {};
  jsaddle-webkitgtk = self.callCabal2nix "jsaddle-webkitgtk" "${jsaddleSrc}/jsaddle-webkitgtk" {};
  jsaddle-wkwebview = overrideCabal (self.callCabal2nix "jsaddle-wkwebview" "${jsaddleDevelopSrc}/jsaddle-wkwebview" {}) (drv: {
    jailbreak = true;
    # HACK(matthewbauer): Can’t figure out why cf-private framework is
    #                     not getting pulled in correctly. Has something
    #                     to with how headers are looked up in xcode.
    preBuild = lib.optionalString (!nixpkgs.stdenv.hostPlatform.useiOSPrebuilt) ''
      mkdir include
      ln -s ${nixpkgs.buildPackages.darwin.cf-private}/Library/Frameworks/CoreFoundation.framework/Headers include/CoreFoundation
      export NIX_CFLAGS_COMPILE="-I$PWD/include $NIX_CFLAGS_COMPILE"
    '';

    libraryFrameworkDepends = (drv.libraryFrameworkDepends or []) ++
      (if nixpkgs.stdenv.hostPlatform.useiOSPrebuilt then [
         "${nixpkgs.buildPackages.darwin.xcode}/Contents/Developer/Platforms/${nixpkgs.stdenv.hostPlatform.xcodePlatform}.platform/Developer/SDKs/${nixpkgs.stdenv.hostPlatform.xcodePlatform}.sdk/System"
       ] else with nixpkgs.buildPackages.darwin; with apple_sdk.frameworks; [
         Cocoa
         WebKit
       ]);
  });

  # another broken test
  # phantomjs has issues with finding the right port
  # jsaddle-warp = dontCheck (addTestToolDepend (self.callCabal2nix "jsaddle-warp" "${jsaddleSrc}/jsaddle-warp" {}));
  jsaddle-warp = overrideCabal (self.callCabal2nix "jsaddle-warp" "${jsaddleSrc}/jsaddle-warp" {}) (drv: {
    doCheck = false;
    postPatch = (drv.postPatch or "") + ''
      substituteInPlace "jsaddle-warp.cabal" \
        --replace "aeson >=0.8.0.2 && <1.3" "aeson" \
        --replace "http-types >=0.8.6 && <0.12" "http-types"
    '';
  });
  jsaddle-dom = doJailbreak (self.callPackage (hackGet ../jsaddle-dom) {});
  inherit (ghcjsDom) ghcjs-dom-jsffi;

  ##
  ## Gargoyle
  ##

  inherit (gargoylePkgs) gargoyle gargoyle-postgresql;

  ##
  ## Misc other dependencies
  ##

  haskell-gi-overloading = dontHaddock (self.callHackage "haskell-gi-overloading" "0.0" {});

  monoidal-containers = self.callCabal2nix "monoidal-containers" (fetchFromGitHub {
    owner = "obsidiansystems";
    repo = "monoidal-containers";
    rev = "79c25ac6bb469bfa92f8fd226684617b6753e955";
    sha256 = "0j2mwf5zhz7cmn01x9v51w8vpx16hrl9x9rcx8fggf21slva8lf8";
  }) {};

  # Needs additional instances
  dependent-sum = self.callCabal2nix "dependent-sum" (fetchFromGitHub {
    owner = "obsidiansystems";
    repo = "dependent-sum";
    rev = "9c649ba33fa95601621b4a3fa3808104dd1ababd";
    sha256 = "1msnzdb79bal1xl2xq2j415n66gi48ynb02pf03wkahymi5dy4yj";
  }) {};
  # Misc new features since Hackage relasese
  dependent-sum-template = self.callCabal2nix "dependent-sum-template" (fetchFromGitHub {
    owner = "mokus0";
    repo = "dependent-sum-template";
    rev = "bfe9c37f4eaffd8b17c03f216c06a0bfb66f7df7";
    sha256 = "1w3s7nvw0iw5li3ry7s8r4651qwgd22hmgz6by0iw3rm64fy8x0y";
  }) {};
  # Not on Hackage yet
  dependent-sum-universe-orphans = self.callCabal2nix "dependent-sum-universe-orphans" (fetchFromGitHub {
    owner = "obsidiansystems";
    repo = "dependent-sum-universe-orphans";
    rev = "8c28c09991cd7c3588ae6db1be59a0540758f5f5";
    sha256 = "0dg32s2mgxav68yw6g7b15w0h0z116zx0qri26gprafgy23bxanm";
  }) {};

}
