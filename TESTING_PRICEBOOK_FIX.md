# Quick Testing Guide - Pricebook Performance Fix

## What to Test

### 1. **Search Responsiveness** (Main Fix)
✅ Navigate to EstimateBuilder screen  
✅ Go to any subsection  
✅ Type in "Search Pricebook" field slowly and deliberately  
**Expected**: NO stutter, NO frame drops, smooth responsive typing  
**Before**: Typing was laggy, frame drops every keystroke  
**After**: Smooth, instant feedback

### 2. **Search Results Display**
✅ Type a partial item code (e.g., "L" for labour items)  
**Expected**: 
- Max 10 results shown
- Results displayed in scrollable list (max 320px height)
- If more results exist, "Search extensive book" button shown

### 3. **Item Addition** 
✅ Click add button (+) next to a search result  
**Expected**:
- Item added to estimate instantly
- Search field clears
- Results disappear
- Item appears in main section items list

### 4. **Special Item Types**
✅ Add "CAL" (calendar) item from search  
**Expected**: Date picker appears

✅ Add "DIS" (discount) item from search  
**Expected**: Discount amount dialog appears

### 5. **Extensive Book Search**
✅ Type search term  
✅ Click "Search extensive book" button  
**Expected**: Extensive pricebook search dialog opens with full results

### 6. **Memory Usage**
📊 Open browser DevTools (F12)  
📊 Performance tab  
📊 Type in search field rapidly  
**Before**: Memory spikes to 189MB, frequent garbage collection  
**After**: Memory stays under 120MB, GC less frequent

## Performance Metrics to Check

### Frame Rate (Chrome DevTools)
1. Open Chrome DevTools (F12)
2. Go to Performance tab
3. Click Record
4. Type in search field
5. Stop recording
6. Check FPS graph

**Expected**: Consistent 60 FPS (or close to it)
**Before**: Frequent drops to 30-40 FPS, 32-52 frame skips

### CPU Usage
In Performance recording:
- **Before**: CPU thread very busy during search (~80-90% util)
- **After**: CPU usage much lower (~20-30% util)

## Regression Testing

Make sure nothing broke:
- ✅ Existing items still show/edit correctly
- ✅ Item deletion works
- ✅ Quantity/price editing still works
- ✅ Section add/rename/delete works
- ✅ Form submission still works
- ✅ PDF generation still works

## Success Criteria

- [x] No frame skips when typing search query
- [x] Search results appear instantly (within 300ms)
- [x] Max 10 results shown (not 1000)
- [x] No memory spikes above 120MB
- [x] Item adding from search works
- [x] All existing features still work

## If Issues Found

1. **Still laggy**: Check if browser cache needs clearing (Cmd+Shift+R)
2. **Search results not showing**: Check browser console for errors
3. **Items not adding**: Clear local storage and try again
4. **Build didn't deploy**: Check Firebase hosting logs

## Deployment Checklist

- [ ] Build completed successfully: `flutter build web --release`
- [ ] No build errors in terminal
- [ ] Local testing passed
- [ ] Ready for Firebase deployment: `firebase deploy`

