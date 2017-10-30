{-# LANGUAGE TemplateHaskell #-}
{-# OPTIONS_GHC -Wno-deprecations #-}
{-# OPTIONS_HADDOCK show-extensions #-}

{-|
Module: Distribution.Simple.Toolkit
Copyright: (c) 2017 Shao Cheng
License: BSD3
Maintainer: astrohavoc@gmail.com
Stability: alpha
Portability: non-portable

This module provides helper functions for writing custom @Setup.hs@ scripts.
-}

module Distribution.Simple.Toolkit
  ( -- * Writing build metadata in @Setup.hs@
    userHooksWithBuildInfo
  , simpleUserHooksWithBuildInfo
  , defaultMainWithBuildInfo
  -- * Retrieving build metadata via Template Haskell
  , packageDescriptionQ
  , packageDescriptionTypedQ
  , localBuildInfoQ
  , localBuildInfoTypedQ
  -- * Convenient functions for working with build metadata
  , getComponentInstallDirs
  , getComponentBuildInfo
  , getGHCLibDir
  , runLBIProgram
  , getLBIProgramOutput
  ) where

import Data.Binary
import qualified Data.ByteString.Lazy as LBS
import qualified Data.ByteString.Unsafe as BS
import Data.Map
import Distribution.Simple
import Distribution.Simple.LocalBuildInfo
import Distribution.Simple.Program
import Distribution.Simple.Setup
import Distribution.Types.BuildInfo
import Distribution.Types.PackageDescription
import Distribution.Verbosity
import Language.Haskell.TH.Syntax
import System.IO.Unsafe

{-|
Attach a post-configure action to a 'UserHooks' which serializes 'PackageDescription' to @.pkg_descr.buildinfo@ and 'LocalBuildInfo' to @.lbi.buildinfo@.
They should be added to your project's @.gitignore@ file.
Don't forget to edit the <https://cabal.readthedocs.io/en/latest/developing-packages.html#custom-setup-scripts custom-setup> stanza of your project's @.cabal@ file and add @cabal-toolkit@ to the dependencies.
-}
userHooksWithBuildInfo :: UserHooks -> UserHooks
userHooksWithBuildInfo hooks =
  hooks
  { postConf =
      \args flags pkg_descr lbi -> do
        encodeFile ".pkg_descr.buildinfo" pkg_descr
        encodeFile ".lbi.buildinfo" lbi
        postConf hooks args flags pkg_descr lbi
  }

simpleUserHooksWithBuildInfo :: UserHooks
simpleUserHooksWithBuildInfo = userHooksWithBuildInfo simpleUserHooks

defaultMainWithBuildInfo :: IO ()
defaultMainWithBuildInfo = defaultMainWithHooks simpleUserHooksWithBuildInfo

syringe :: FilePath -> Q Type -> Q Exp
syringe p t = do
  buf <- runIO $ LBS.readFile p
  [|unsafePerformIO $ do
      bs <-
        BS.unsafePackAddressLen
          $(lift $ LBS.length buf)
          $(pure $ LitE $ StringPrimL $ LBS.unpack buf)
      pure ((decode $ LBS.fromStrict bs) :: $(t))|]

{-|
The Template Haskell splice to retrieve 'PackageDescription'.
-}
packageDescriptionQ :: Q Exp
packageDescriptionQ = syringe ".pkg_descr.buildinfo" [t|PackageDescription|]

packageDescriptionTypedQ :: Q (TExp PackageDescription)
packageDescriptionTypedQ = unsafeTExpCoerce packageDescriptionQ

{-|
The Template Haskell splice to retrieve 'LocalBuildInfo'.
-}
localBuildInfoQ :: Q Exp
localBuildInfoQ = syringe ".lbi.buildinfo" [t|LocalBuildInfo|]

localBuildInfoTypedQ :: Q (TExp LocalBuildInfo)
localBuildInfoTypedQ = unsafeTExpCoerce localBuildInfoQ

{-|
Retrieve the 'InstallDirs' corresponding to a 'ComponentName', assuming that component does exist and is unique.
-}
getComponentInstallDirs ::
     PackageDescription
  -> LocalBuildInfo
  -> ComponentName
  -> InstallDirs FilePath
getComponentInstallDirs pkg_descr lbi k =
  absoluteComponentInstallDirs
    pkg_descr
    lbi
    (componentUnitId $ getComponentLocalBuildInfo lbi k)
    NoCopyDest

{-|
Retrieve the 'BuildInfo' corresponding to a 'ComponentName', assuming that component does exist and is unique.
-}
getComponentBuildInfo :: PackageDescription -> ComponentName -> BuildInfo
getComponentBuildInfo pkg_descr k =
  componentBuildInfo $ getComponent pkg_descr k

{-|
Equivalent to what you get from @ghc --print-libdir@.
-}
getGHCLibDir :: LocalBuildInfo -> FilePath
getGHCLibDir lbi = compilerProperties (compiler lbi) ! "LibDir"

{-|
Run a 'Program' with default 'Verbosity'.
-}
runLBIProgram :: LocalBuildInfo -> Program -> [ProgArg] -> IO ()
runLBIProgram lbi prog =
  runDbProgram
    (fromFlagOrDefault normal $ configVerbosity $ configFlags lbi)
    prog
    (withPrograms lbi)

{-|
Run a 'Program' and retrieve @stdout@ with default 'Verbosity'.
-}
getLBIProgramOutput :: LocalBuildInfo -> Program -> [ProgArg] -> IO String
getLBIProgramOutput lbi prog =
  getDbProgramOutput
    (fromFlagOrDefault normal $ configVerbosity $ configFlags lbi)
    prog
    (withPrograms lbi)