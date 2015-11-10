{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}

-- | Make changes to the stack yaml file

module Stack.ConfigCmd
       ( ConfigCmdAdd(..)
       , ConfigCmdSet(..)
       , cfgCmdName
       , cfgCmdAdd
       , cfgCmdAddName
       , cfgCmdSet
       , cfgCmdSetName) where

import           Control.Monad.Catch (MonadMask, throwM, MonadThrow)
import           Control.Monad.IO.Class
import           Control.Monad.Logger
import           Control.Monad.Reader (MonadReader, asks)
import           Control.Monad.Trans.Control (MonadBaseControl)
import qualified Data.ByteString as S
import qualified Data.HashMap.Strict as HMap
import           Data.Monoid
import           Data.Text (Text)
import           Data.Vector (Vector)
import qualified Data.Vector as V
import qualified Data.Yaml as Yaml
import           Network.HTTP.Client.Conduit (HasHttpManager)
import           Path
import           Stack.BuildPlan
import           Stack.Init
import           Stack.Types

data ConfigCmdAdd = ConfigCmdAddExtraDep PackageIdentifier
data ConfigCmdSet
    = ConfigCmdSetResolver AbstractResolver
    | ConfigCmdSetField Text Text -- Field Value

cfgCmdAdd :: (MonadIO m, MonadBaseControl IO m, MonadMask m, MonadReader env m, HasConfig env, HasBuildConfig env, HasHttpManager env, HasGHCVariant env, MonadThrow m, MonadLogger m)
          => ConfigCmdAdd -> m ()


cfgCmdAdd (ConfigCmdAddExtraDep newDep) = do
    stackYaml <-
        fmap bcStackYaml (asks getBuildConfig)
    let stackYamlFp =
            toFilePath stackYaml
    -- We don't need to worry about checking for a valid yaml here
    (projectYamlConfig :: Yaml.Object) <-
        liftIO (Yaml.decodeFileEither stackYamlFp) >>=
        either throwM return
    extraDepsArr <- yamlExtraDeps projectYamlConfig
    let newDepTextArr =
            V.singleton
                (packageIdentifierText newDep)
        projectYamlConfig' =
            HMap.insert
                "extra-deps"
                (Yaml.toJSON $ extraDepsArr <> newDepTextArr)
                projectYamlConfig
    liftIO
        (S.writeFile
             stackYamlFp
             (Yaml.encode projectYamlConfig'))
    return ()    
yamlExtraDeps :: MonadThrow m
              => Yaml.Object -> m (Vector Text)
yamlExtraDeps stackYaml =
    either
        error
        return
        (Yaml.parseEither
             (\obj ->
                   obj Yaml..: "extra-deps")
             stackYaml)

cfgCmdSet :: (MonadIO m, MonadBaseControl IO m, MonadMask m, MonadReader env m, HasConfig env, HasBuildConfig env, HasHttpManager env, HasGHCVariant env, MonadThrow m, MonadLogger m)
          => ConfigCmdSet -> m ()
cfgCmdSet (ConfigCmdSetResolver newResolver) = do
    stackYaml <-
        fmap bcStackYaml (asks getBuildConfig)
    let stackYamlFp =
            toFilePath stackYaml
    -- We don't need to worry about checking for a valid yaml here
    (projectYamlConfig :: Yaml.Object) <-
        liftIO (Yaml.decodeFileEither stackYamlFp) >>=
        either throwM return
    newResolverText <-
        fmap resolverName (makeConcreteResolver newResolver)
    -- We checking here that the snapshot actually exists
    snap <- parseSnapName newResolverText
    _ <- loadMiniBuildPlan snap
    let projectYamlConfig' =
            HMap.insert
                "resolver"
                (Yaml.String newResolverText)
                projectYamlConfig
    liftIO
        (S.writeFile
             stackYamlFp
             (Yaml.encode projectYamlConfig'))
    return ()
cfgCmdSet (ConfigCmdSetField _ _) = error "stack config set FIELD VALUE not implemented"

cfgCmdName :: String
cfgCmdName = "config"

cfgCmdSetName :: String
cfgCmdSetName = "set"

cfgCmdAddName :: String
cfgCmdAddName = "add"
