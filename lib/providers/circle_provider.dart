import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class CircleProvider extends ChangeNotifier {
  Map<String, dynamic>? _circleData;
  List<String> _followedParties = [];
  bool _isLoaded = false;

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  Map<String, dynamic>? get circleData => _circleData;
  List<String> get followedParties => List.unmodifiable(_followedParties);
  bool get isLoaded => _isLoaded;

  CircleProvider() {
    loadCircleData();
  }

  Future<void> loadCircleData() async {
    _isLoaded = false;
    notifyListeners();

    final user = _auth.currentUser;
    if (user == null) return;

    final userDoc = await _firestore.collection('users').doc(user.uid).get();
    final data = userDoc.data();

    _circleData = data?['circle'];

    final parties = data?['followedParties'];
    if (parties != null && parties is List) {
      _followedParties = List<String>.from(parties);
    } else {
      _followedParties = [];
    }

    _isLoaded = true;
    notifyListeners();
  }

  Future<void> setCircle(Map<String, dynamic> circle) async {
    _circleData = circle;
    notifyListeners();

    final user = _auth.currentUser;
    if (user == null) return;

    await _firestore.collection('users').doc(user.uid).set({
      'circle': circle,
    }, SetOptions(merge: true));
  }

  bool isFollowing(String partyName) {
    return _followedParties.contains(partyName);
  }

  Future<void> followParty(String partyName) async {
    if (!_followedParties.contains(partyName)) {
      _followedParties.add(partyName);
      notifyListeners();
      await _updateFollowedPartiesInFirestore();
    }
  }

  Future<void> unfollowParty(String partyName) async {
    if (_followedParties.contains(partyName)) {
      _followedParties.remove(partyName);
      notifyListeners();
      await _updateFollowedPartiesInFirestore();
    }
  }

  Future<void> _updateFollowedPartiesInFirestore() async {
    final user = _auth.currentUser;
    if (user == null) return;

    await _firestore.collection('users').doc(user.uid).set({
      'followedParties': _followedParties,
    }, SetOptions(merge: true));
  }
}