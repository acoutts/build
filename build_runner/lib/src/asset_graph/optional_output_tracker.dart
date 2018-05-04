// Copyright (c) 2018, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:build/build.dart';

import '../generate/phase.dart';
import 'graph.dart';
import 'node.dart';

/// A cache of the results of checking whether outputs from optional build steps
/// were required by in the current build.
///
/// An optional output becomes required if:
/// - Any of it's transitive outputs is non-optional.
/// - It was output by the same build step as any required output.
///
/// Any outputs from non-optional phases are aways considered required.
///
/// Non-required optional output might still exist in the generated directory an
/// the asset graph but we should avoid serving them, outputting them in the
/// merged directories, or considering a failed output as an overall.
class OptionalOutputTracker {
  final _checkedOutputs = <AssetId, bool>{};
  final AssetGraph _assetGraph;
  final List<BuildPhase> _buildPhases;

  OptionalOutputTracker(this._assetGraph, this._buildPhases);

  /// Returns whether [output] is required.
  ///
  /// If necessary crawls transitive outputs that read [output] or any other
  /// assets generated by the same phase until it finds on which is required.
  ///
  /// [currentlyChecking] is used to aovid repeatedly checking the same outputs.
  bool isRequired(AssetId output, [Set<AssetId> currentlyChecking]) {
    currentlyChecking ??= new Set<AssetId>();
    if (currentlyChecking.contains(output)) return false;
    currentlyChecking.add(output);

    final node = _assetGraph.get(output);
    if (node is! GeneratedAssetNode) return true;
    final generatedNode = node as GeneratedAssetNode;
    final phase = _buildPhases[generatedNode.phaseNumber];
    if (!phase.isOptional) return true;
    return _checkedOutputs.putIfAbsent(
        output,
        () =>
            generatedNode.outputs
                .any((o) => isRequired(o, currentlyChecking)) ||
            _assetGraph
                .outputsForPhase(output.package, generatedNode.phaseNumber)
                .where((n) => n.primaryInput == generatedNode.primaryInput)
                .map((n) => n.id)
                .any((o) => isRequired(o, currentlyChecking)));
  }

  /// Clears the cache of which assets were required.
  ///
  /// If the tracker is used across multiple builds it must be reset in between
  /// each one.
  void reset() {
    _checkedOutputs.clear();
  }
}