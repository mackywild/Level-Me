class FeQuestion {
 const FeQuestion({required this.id,required this.section,required this.domain,required this.stem,required this.options,required this.answerIndex,required this.explanation});
 final String id,section,domain,stem,explanation;
 final List<String> options;
 final int answerIndex;
 factory FeQuestion.fromJson(Map<String,dynamic> j)=>FeQuestion(
  id:j['id'] as String,section:j['section'] as String,domain:j['domain'] as String,
  stem:j['stem'] as String,options:(j['options'] as List).cast<String>(),
  answerIndex:j['answerIndex'] as int,explanation:j['explanation'] as String);
}
