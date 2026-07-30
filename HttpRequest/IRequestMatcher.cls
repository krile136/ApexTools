/**
 * @description Custom predicate for MockHttpRequestHandler request matching.
 *
 * Implement this in a test class (typically as an inner class) for conditions
 * the when() criteria builder cannot express, e.g. inspecting the JSON structure
 * of the request body:
 *
 * <pre>
 * private class UpsertBodyMatcher implements IRequestMatcher {
 *   public Boolean matches(HttpRequest request) {
 *     Map&lt;String, Object&gt; body = (Map&lt;String, Object&gt;) JSON.deserializeUntyped(request.getBody());
 *     return body.containsKey('record');
 *   }
 * }
 * // mock.when(new UpsertBodyMatcher()).respond(okBody, 200);
 * </pre>
 */
public interface IRequestMatcher {
  Boolean matches(HttpRequest request);
}
