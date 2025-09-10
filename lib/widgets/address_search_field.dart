import 'package:flutter/material.dart';
import '../services/address_search_service.dart';
import 'dart:async';

class AddressSearchField extends StatefulWidget {
  final TextEditingController controller;
  final String labelText;
  final String? helperText;
  final bool isRequired;
  final Function(AddressSearchResult)? onAddressSelected;
  final String? Function(String?)? validator;

  const AddressSearchField({
    super.key,
    required this.controller,
    this.labelText = 'Address',
    this.helperText,
    this.isRequired = false,
    this.onAddressSelected,
    this.validator,
  });

  @override
  State<AddressSearchField> createState() => _AddressSearchFieldState();
}

class _AddressSearchFieldState extends State<AddressSearchField> {
  Timer? _debounceTimer;
  List<AddressSearchResult> _suggestions = [];
  bool _isSearching = false;
  final FocusNode _focusNode = FocusNode();
  final LayerLink _layerLink = LayerLink();
  OverlayEntry? _overlayEntry;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_onFocusChange);
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _focusNode.removeListener(_onFocusChange);
    _focusNode.dispose();
    _removeOverlay();
    super.dispose();
  }

  void _onFocusChange() {
    if (!_focusNode.hasFocus) {
      _hideSuggestions();
    }
  }

  void _onTextChanged(String query) {
    _debounceTimer?.cancel();
    
    if (query.trim().length < 3) {
      _hideSuggestions();
      return;
    }

    setState(() {
      _isSearching = true;
    });

    _debounceTimer = Timer(const Duration(milliseconds: 500), () {
      _searchAddresses(query);
    });
  }

  Future<void> _searchAddresses(String query) async {
    try {
      final results = await AddressSearchService.searchAddresses(query, limit: 8);
      
      if (mounted) {
        setState(() {
          _suggestions = results;
          _isSearching = false;
        });
        
        if (results.isNotEmpty) {
          _showOverlay();
        } else {
          _removeOverlay();
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSearching = false;
        });
        _removeOverlay();
      }
    }
  }

  void _showOverlay() {
    _removeOverlay();
    
    _overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        width: MediaQuery.of(context).size.width - 32,
        child: CompositedTransformFollower(
          link: _layerLink,
          showWhenUnlinked: false,
          offset: const Offset(0, 60),
          child: Material(
            elevation: 8,
            borderRadius: BorderRadius.circular(8),
            child: Container(
              constraints: const BoxConstraints(maxHeight: 300),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey[300]!),
              ),
              child: ListView.builder(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: _suggestions.length,
                itemBuilder: (context, index) {
                  final suggestion = _suggestions[index];
                  return ListTile(
                    dense: true,
                    leading: const Icon(Icons.location_on, size: 20, color: Colors.grey),
                    title: Text(
                      suggestion.address,
                      style: const TextStyle(fontSize: 14),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (suggestion.city != null || suggestion.region != null)
                          Text(
                            [suggestion.city, suggestion.region, suggestion.country]
                                .where((e) => e != null && e.isNotEmpty)
                                .join(', '),
                            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                          ),
                        if (suggestion.distanceKm != null)
                          Text(
                            '${suggestion.distanceKm!.toStringAsFixed(1)} km from office',
                            style: TextStyle(fontSize: 11, color: Colors.blue[600], fontWeight: FontWeight.w500),
                          ),
                      ],
                    ),
                    onTap: () => _selectAddress(suggestion),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );

    Overlay.of(context).insert(_overlayEntry!);
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  void _selectAddress(AddressSearchResult address) {
    widget.controller.text = address.address;
    widget.onAddressSelected?.call(address);
    _hideSuggestions();
    _focusNode.unfocus();
  }

  void _hideSuggestions() {
    setState(() {
      _suggestions.clear();
    });
    _removeOverlay();
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _layerLink,
      child: TextFormField(
        controller: widget.controller,
        focusNode: _focusNode,
        decoration: InputDecoration(
          labelText: widget.labelText,
          helperText: widget.helperText,
          prefixIcon: const Icon(Icons.search),
          suffixIcon: _isSearching
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: Padding(
                    padding: EdgeInsets.all(12.0),
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : widget.controller.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        widget.controller.clear();
                        _hideSuggestions();
                      },
                    )
                  : null,
          border: const OutlineInputBorder(),
        ),
        textCapitalization: TextCapitalization.words,
        maxLines: 2,
        onChanged: _onTextChanged,
        validator: widget.validator ??
            (widget.isRequired
                ? (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Please enter ${widget.labelText.toLowerCase()}';
                    }
                    return null;
                  }
                : null),
      ),
    );
  }
}
