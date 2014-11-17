// Copyright 2014 Google Inc. All rights reserved.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//    http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

package com.google.devtools.build.lib.view;

import com.google.common.base.Preconditions;
import com.google.common.base.Predicate;
import com.google.common.collect.ImmutableList;
import com.google.common.collect.Iterables;
import com.google.devtools.build.lib.actions.Artifact;
import com.google.devtools.build.lib.packages.RuleClass.Builder;
import com.google.devtools.build.lib.util.FileType;
import com.google.devtools.build.lib.util.FileTypeSet;
import com.google.devtools.build.lib.view.RuleConfiguredTarget.Mode;

import java.util.LinkedHashSet;
import java.util.Set;

/**
 * Contains a sequence of prerequisite artifacts and supplies methods for filtering and reporting
 * errors on those artifacts.
 */
public final class PrerequisiteArtifacts {
  private final RuleContext ruleContext;
  private final String attributeName;
  private final ImmutableList<Artifact> artifacts;

  private PrerequisiteArtifacts(
      RuleContext ruleContext, String attributeName, ImmutableList<Artifact> artifacts) {
    this.ruleContext = Preconditions.checkNotNull(ruleContext);
    this.attributeName = Preconditions.checkNotNull(attributeName);
    this.artifacts = Preconditions.checkNotNull(artifacts);
  }

  /**
   * For the specified attribute "attributeName" (which must be of type
   * list(label)), resolve all the labels into ConfiguredTargets (for the
   * configuration appropriate to the attribute) and return their build
   * artifacts as a {@link PrerequisiteArtifacts} instance.
   *
   * @param attributeName the name of the attribute to traverse
   */
  public static PrerequisiteArtifacts get(
      RuleContext ruleContext, String attributeName, Mode mode) {
    Set<Artifact> result = new LinkedHashSet<>();
    for (FileProvider target :
        ruleContext.getPrerequisites(attributeName, mode, FileProvider.class)) {
      Iterables.addAll(result, target.getFilesToBuild());
    }
    return new PrerequisiteArtifacts(ruleContext, attributeName, ImmutableList.copyOf(result));
  }

  /**
   * Returns the artifacts this instance contains in an {@link ImmutableList}.
   */
  public ImmutableList<Artifact> list() {
    return artifacts;
  }

  private PrerequisiteArtifacts filter(Predicate<String> fileType, boolean errorsForNonMatching) {
    ImmutableList.Builder<Artifact> filtered = new ImmutableList.Builder<Artifact>();

    for (Artifact artifact : artifacts) {
      if (fileType.apply(artifact.getFilename())) {
        filtered.add(artifact);
      } else if (errorsForNonMatching) {
        ruleContext.attributeError(
            attributeName,
            String.format("%s does not match expected type: %s", artifact, fileType));
      }
    }

    return new PrerequisiteArtifacts(ruleContext, attributeName, filtered.build());
  }

  /**
   * Returns an equivalent instance but only containing artifacts of the given type, reporting
   * errors for non-matching artifacts.
   */
  public PrerequisiteArtifacts errorsForNonMatching(FileType fileType) {
    return filter(fileType, /*errorsForNonMatching=*/true);
  }

  /**
   * Returns an equivalent instance but only containing artifacts of the given types, reporting
   * errors for non-matching artifacts.
   */
  public PrerequisiteArtifacts errorsForNonMatching(FileTypeSet fileTypeSet) {
    return filter(fileTypeSet, /*errorsForNonMatching=*/true);
  }

  /**
   * Returns an equivalent instance but only containing artifacts of the given type.
   */
  public PrerequisiteArtifacts filter(FileType fileType) {
    return filter(fileType, /*errorsForNonMatching=*/false);
  }

  /**
   * Returns an equivalent instance but only containing artifacts of the given types.
   */
  public PrerequisiteArtifacts filter(FileTypeSet fileTypeSet) {
    return filter(fileTypeSet, /*errorsForNonMatching=*/false);
  }
}
