import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_redux/flutter_redux.dart';
import 'package:redux/redux.dart';

const apiUrl =
    'https://c818-2400-adc5-46c-4c00-50e1-9094-b60a-2453.eu.ngrok.io/api/persons/full/';

@immutable
class Person {
  final String id;
  final String name;
  final int age;
  final String imageUrl;
  final Uint8List? imageData;
  final bool isLoading;

  Person copiedWith([bool? isLoading, Uint8List? imageData]) => Person(
      id: id,
      name: name,
      age: age,
      imageUrl: imageUrl,
      imageData: imageData ?? this.imageData,
      isLoading: isLoading ?? this.isLoading);

  const Person({
    required this.id,
    required this.name,
    required this.age,
    required this.imageUrl,
    required this.imageData,
    required this.isLoading,
  });

  Person.fromJson(Map<String, dynamic> json)
      : id = json['id'] as String,
        name = json['name'] as String,
        age = json['age'] as int,
        imageUrl = json['imageUrl'] as String,
        imageData = null,
        isLoading = false;

  @override
  String toString() => 'Person (id = $id, $name, $age years old)';
}

Future<Iterable<Person>> getPersons() => HttpClient()
    .getUrl(Uri.parse(apiUrl))
    .then((req) => req.close())
    .then((res) => res.transform(utf8.decoder).join())
    .then((str) => json.decode(str) as List<dynamic>)
    .then((list) => list.map((e) => Person.fromJson(e)));

@immutable
abstract class Action {
  const Action();
}

@immutable
class LoadPersonAction extends Action {
  const LoadPersonAction();
}

@immutable
class SuccessfullyFetchedPersonAction extends Action {
  final Iterable<Person> persons;

  const SuccessfullyFetchedPersonAction({required this.persons});
}

@immutable
class FailedToFetchPersonAction extends Action {
  final Object error;

  const FailedToFetchPersonAction({required this.error});
}

@immutable
class State {
  final bool isLoading;
  final Iterable<Person>? fetchedPersons;
  final Object? error;

  Iterable<Person>? get sortedFetchedPersons => fetchedPersons?.toList()
    ?..sort((p1, p2) => int.parse(p1.id).compareTo(int.parse(p2.id)));

  const State(
      {required this.isLoading,
      required this.fetchedPersons,
      required this.error});

  const State.empty()
      : isLoading = false,
        fetchedPersons = null,
        error = null;
}

@immutable
class LoadPersonImageAction extends Action {
  final String personId;

  const LoadPersonImageAction({required this.personId});
}

@immutable
class SuccessfullyLoadedPersonImageAction extends Action {
  final String personId;
  final Uint8List imageData;

  const SuccessfullyLoadedPersonImageAction({
    required this.personId,
    required this.imageData,
  });
}

State reducer(State oldState, action) {
  if (action is LoadPersonAction) {
    return const State(isLoading: true, fetchedPersons: null, error: null);
  } else if (action is SuccessfullyFetchedPersonAction) {
    return State(isLoading: false, fetchedPersons: action.persons, error: null);
  } else if (action is FailedToFetchPersonAction) {
    return State(
        error: action.error,
        isLoading: false,
        fetchedPersons: oldState.fetchedPersons);
  } else if (action is LoadPersonImageAction) {
    final person = oldState.fetchedPersons
        ?.firstWhere((element) => element.id == action.personId);
    if (person != null) {
      return State(
        isLoading: false,
        error: oldState.error,
        fetchedPersons: oldState.fetchedPersons
            ?.where((p) => p.id != person.id)
            .followedBy([person.copiedWith(true)]),
      );
    } else {
      return oldState;
    }
  } else if (action is SuccessfullyLoadedPersonImageAction) {
    final person = oldState.fetchedPersons
        ?.firstWhere((element) => element.id == action.personId);
    if (person != null) {
      return State(
        isLoading: false,
        error: oldState.error,
        fetchedPersons: oldState.fetchedPersons
            ?.where((p) => p.id != person.id)
            .followedBy([person.copiedWith(false, action.imageData)]),
      );
    } else {
      return oldState;
    }
  } else {
    return oldState;
  }
}

void loadPersonMiddleware(Store<State> store, action, NextDispatcher next) {
  if (action is LoadPersonAction) {
    getPersons()
        .then((value) =>
            store.dispatch(SuccessfullyFetchedPersonAction(persons: value)))
        .catchError(
            (e) => {store.dispatch(FailedToFetchPersonAction(error: e))});
  }
  next(action);
}

void loadPersonImageMiddleware(
    Store<State> store, action, NextDispatcher next) {
  if (action is LoadPersonImageAction) {
    final person =
        store.state.fetchedPersons?.firstWhere((p) => p.id == action.personId);
    if (person != null) {
      final url = person.imageUrl;
      final bundle = NetworkAssetBundle(Uri.parse(url));
      bundle
          .load(url)
          .then((value) => value.buffer.asUint8List())
          .then((data) => store.dispatch(SuccessfullyLoadedPersonImageAction(
                personId: person.id,
                imageData: data,
              )));
    }
  }
  next(action);
}

class SecondHome extends StatelessWidget {
  const SecondHome({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final store = Store(
      reducer,
      initialState: const State.empty(),
      middleware: [
        loadPersonMiddleware,
        loadPersonImageMiddleware,
      ],
    );
    return Scaffold(
      appBar: AppBar(
        title: const Text('Redux'),
      ),
      body: StoreProvider(
        store: store,
        child: Column(
          children: [
            TextButton(
                onPressed: () {
                  store.dispatch(const LoadPersonAction());
                },
                child: const Text('Load Persons')),
            StoreConnector<State, bool>(
                builder: (context, isLoading) {
                  if (isLoading) {
                    return const CircularProgressIndicator.adaptive();
                  } else {
                    return const SizedBox();
                  }
                },
                converter: (store) => store.state.isLoading),
            StoreConnector<State, Iterable<Person>?>(
                builder: (context, persons) {
                  if (persons == null) {
                    return const SizedBox();
                  } else {
                    return Expanded(
                      child: ListView.builder(
                          itemCount: persons.length,
                          itemBuilder: (context, index) {
                            final person = persons.elementAt(index);
                            final infoWidget = Text('${person.age} years old!');
                            final Widget subtitle = person.imageData == null
                                ? infoWidget
                                : Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      infoWidget,
                                      Image.memory(person.imageData!),
                                    ],
                                  );
                            final Widget trailing = person.isLoading
                                ? const CircularProgressIndicator.adaptive()
                                : TextButton(
                                    onPressed: () {
                                      store.dispatch(LoadPersonImageAction(
                                          personId: person.id));
                                    },
                                    child: const Text('Load Image'),
                                  );
                            return ListTile(
                              title: Text(person.name),
                              subtitle: subtitle,
                              trailing: trailing,
                            );
                          }),
                    );
                  }
                },
                converter: (store) => store.state.sortedFetchedPersons)
          ],
        ),
      ),
    );
  }
}
