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

package com.google.devtools.build.lib.bazel.rules;

import static com.google.devtools.build.lib.packages.Attribute.attr;
import static com.google.devtools.build.lib.packages.Type.BOOLEAN;
import static com.google.devtools.build.lib.packages.Type.LICENSE;
import static com.google.devtools.build.lib.packages.Type.STRING_LIST;

import com.google.common.collect.ImmutableSet;
import com.google.devtools.build.lib.packages.RuleClass;
import com.google.devtools.build.lib.packages.RuleClass.Builder;
import com.google.devtools.build.lib.packages.RuleClass.Builder.RuleClassType;
import com.google.devtools.build.lib.view.BaseRuleClasses;
import com.google.devtools.build.lib.view.BlazeRule;
import com.google.devtools.build.lib.view.RuleDefinition;
import com.google.devtools.build.lib.view.RuleDefinitionEnvironment;

/**
 * The foundational rule templates to help in real rule construction. Only attributes truly common
 * to all rules go in here.  Attributes such as "out", "outs", "src" and "srcs" exhibit enough
 * variation that we declare them explicitly for each rule.  This leads to stricter error checking
 * and prevents users from inadvertently using an attribute that doesn't actually do anything.
 */
public class BazelBaseRuleClasses {
  public static final ImmutableSet<String> ALLOWED_RULE_CLASSES =
      ImmutableSet.of("filegroup", "genrule", "Fileset");

  /**
   * A base rule for all binary rules.
   */
  @BlazeRule(name = "$binary_base_rule",
               type = RuleClassType.ABSTRACT)
  public static final class BinaryBaseRule implements RuleDefinition {
    @Override
    public RuleClass build(Builder builder, RuleDefinitionEnvironment env) {
      return builder
          .add(attr("args", STRING_LIST).nonconfigurable())
          .add(attr("output_licenses", LICENSE).nonconfigurable())
          .add(attr("$is_executable", BOOLEAN).nonconfigurable().value(true))
          .build();
    }
  }

  /**
   * Rule class for rules in error.
   */
  @BlazeRule(name = "$error_rule",
               type = RuleClassType.ABSTRACT,
               ancestors = { BaseRuleClasses.BaseRule.class })
  public static final class ErrorRule implements RuleDefinition {
    @Override
    public RuleClass build(Builder builder, RuleDefinitionEnvironment env) {
      return builder
          .publicByDefault()
          .build();
    }
  }
}